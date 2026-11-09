# infra

One-time AWS setup for the File Library ingestion: a daily Lambda that copies new ENTSO-E File Library files into an immutable S3 raw bucket, with an email alert when a run fails.

```
EventBridge (daily 06:00 UTC) ──► Lambda: entsoe-file-library-ingest ──► S3: raw/file_library/...
                                     │  reads credentials from SSM
                                     └─ errors ──► CloudWatch alarm ──► SNS ──► email
```

Create the pieces in this order. All commands are PowerShell, run from the repo root, in region `eu-west-1`.

Look up the account ID first, so it never has to be written into this public repo:

```powershell
$AccountId = aws sts get-caller-identity --query Account --output text
```

## 1. Raw bucket

Holds every version of every File Library file. Block Public Access keeps it private. Versioning protects against deletes: a deleted file stays recoverable as an older version. Overwrites are prevented by the Lambda itself, which writes with `IfNoneMatch="*"`.

```powershell
aws s3api create-bucket --bucket entsoe-power-raw-joaoribeiro --region eu-west-1 --create-bucket-configuration LocationConstraint=eu-west-1
aws s3api put-public-access-block --bucket entsoe-power-raw-joaoribeiro --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-versioning --bucket entsoe-power-raw-joaoribeiro --versioning-configuration Status=Enabled
```

## 2. ENTSO-E credentials in SSM Parameter Store

The Lambda reads the ENTSO-E username and password from SSM instead of environment variables, which anyone with access to the function's configuration could read in plain text.

The username isn't secret:

```powershell
aws ssm put-parameter --name /entsoe/username --type String --value "<YOUR_ENTSOE_USERNAME>" --region eu-west-1
```

Create the password in the console, so it doesn't end up in your shell history: **Systems Manager → Parameter Store → Create parameter**, name `/entsoe/password`, type **SecureString**, default key `aws/ssm`.

## 3. IAM role

The identity the Lambda runs as. Two parts:

- **Trust** ([iam/file-library-lambda-trust.json](iam/file-library-lambda-trust.json)): who may use the role. Only the Lambda service.
- **Permissions**: what the role may do. Writing logs (the AWS-managed `AWSLambdaBasicExecutionRole`), plus [iam/file-library-lambda-policy.json](iam/file-library-lambda-policy.json): read/write objects in the bucket, list the bucket (so a missing file returns 404 instead of 403), and read the `/entsoe/*` parameters.

```powershell
aws iam create-role --role-name entsoe-file-library-lambda --assume-role-policy-document file://infra/iam/file-library-lambda-trust.json
aws iam attach-role-policy --role-name entsoe-file-library-lambda --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam put-role-policy --role-name entsoe-file-library-lambda --policy-name file-library-access --policy-document file://infra/iam/file-library-lambda-policy.json
```

## 4. Lambda function

Build the zip first, then create the function.

- **Timeout 900 s:** the maximum. A first run over a week of files took about 2 minutes.
- **Memory 3008 MB:** the largest files are about 610 MB and are held in memory while downloading. 1024 MB ran out of memory; peak use at 3008 MB was 1.9 GB.

```powershell
.\ingestion\file_library\deploy.ps1 -BuildOnly
aws lambda create-function --function-name entsoe-file-library-ingest --runtime python3.13 --handler handler.lambda_handler --role "arn:aws:iam::${AccountId}:role/entsoe-file-library-lambda" --zip-file fileb://ingestion/file_library/lambda.zip --timeout 900 --memory-size 3008 --environment "Variables={RAW_BUCKET=entsoe-power-raw-joaoribeiro}" --region eu-west-1
```

## 5. Daily schedule

An EventBridge rule runs the Lambda every day at 06:00 UTC. The Lambda must also allow that rule to invoke it.

```powershell
aws events put-rule --name entsoe-file-library-daily --schedule-expression "cron(0 6 * * ? *)" --region eu-west-1
aws lambda add-permission --function-name entsoe-file-library-ingest --statement-id eventbridge-daily --action lambda:InvokeFunction --principal events.amazonaws.com --source-arn "arn:aws:events:eu-west-1:${AccountId}:rule/entsoe-file-library-daily" --region eu-west-1
aws events put-targets --rule entsoe-file-library-daily --targets "Id=lambda,Arn=arn:aws:lambda:eu-west-1:${AccountId}:function:entsoe-file-library-ingest" --region eu-west-1
```

## 6. Failure alarm

A failed run (an error raised by the handler, a timeout or running out of memory) increases the Lambda's `Errors` metric. The alarm emails you when there's at least one error in an hour. Hours without any run don't count as failures.

```powershell
aws sns create-topic --name entsoe-pipeline-alerts --region eu-west-1
aws sns subscribe --topic-arn "arn:aws:sns:eu-west-1:${AccountId}:entsoe-pipeline-alerts" --protocol email --notification-endpoint "<YOUR_EMAIL>" --region eu-west-1
```

Click the confirmation link in the email AWS sends, or no alerts will arrive. Then create the alarm:

```powershell
aws cloudwatch put-metric-alarm --alarm-name entsoe-file-library-ingest-errors --namespace AWS/Lambda --metric-name Errors --dimensions Name=FunctionName,Value=entsoe-file-library-ingest --statistic Sum --period 3600 --evaluation-periods 1 --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold --treat-missing-data notBreaching --alarm-actions "arn:aws:sns:eu-west-1:${AccountId}:entsoe-pipeline-alerts" --region eu-west-1
```

Test it (you should get an email; the alarm returns to OK on its own):

```powershell
aws cloudwatch set-alarm-state --alarm-name entsoe-file-library-ingest-errors --state-value ALARM --state-reason "Testing the alert email" --region eu-west-1
```

This alarm catches runs that fail, not runs that never happen (for example a broken schedule).

## Updating the code

After changing `handler.py`:

```powershell
.\ingestion\file_library\deploy.ps1
```

## Running it by hand

Start a run without waiting for it, then follow the logs (`Ctrl+C` stops following, not the run):

```powershell
aws lambda invoke --function-name entsoe-file-library-ingest --invocation-type Event --region eu-west-1 response.json
aws logs tail /aws/lambda/entsoe-file-library-ingest --follow --region eu-west-1
```
