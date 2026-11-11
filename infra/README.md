# infra

One-time setup for the File Library ingestion: a daily Lambda that copies new ENTSO-E File Library files into an immutable S3 raw bucket, with an email alert when a run fails (sections 1–6), and the Snowflake warehouse that reads them (section 7).

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

## 7. Snowflake

[snowflake/setup.sql](snowflake/setup.sql) creates the warehouse, the `ENTSOE` database with its `RAW`, `STAGING` and `MARTS` schemas, a monthly credit limit, the `ENTSOE_SERVICE` role, the `ENTSOE_SVC` service user (for dbt and loads), read-only access to the raw bucket, the CSV file format, and email alerts for failed loads. The `raw_*.sql` files and `load_file_library.sql` then create the tables and the daily load.

```
Snowflake ──(storage integration ENTSOE_S3)──► IAM role entsoe-snowflake-s3 ──(read only)──► S3 raw/file_library/
```

Run it in a Snowsight worksheet, section by section, together with the steps below. The Snowflake account is in `eu-west-3` and the bucket in `eu-west-1`, so loads pay a small cross-region transfer fee (about 0.02 USD/GB).

### Service user key

`ENTSOE_SVC` is a `TYPE = SERVICE` user: no password, key-pair login only. Generate the keys outside the repo (OpenSSL ships with Git for Windows):

```powershell
Set-Alias openssl "C:\Program Files\Git\mingw64\bin\openssl.exe"
New-Item -ItemType Directory -Force "$HOME\.snowflake" | Out-Null
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$HOME\.snowflake\entsoe_svc_key.p8"
openssl pkey -in "$HOME\.snowflake\entsoe_svc_key.p8" -pubout -out "$HOME\.snowflake\entsoe_svc_key.pub"
(Get-Content "$HOME\.snowflake\entsoe_svc_key.pub" | Where-Object { $_ -notmatch "-----" }) -join "" | Set-Clipboard
```

Then, in the worksheet only (the key is not part of `setup.sql`, because it gets rotated):

```sql
ALTER USER ENTSOE_SVC SET RSA_PUBLIC_KEY = '<paste>';
DESC USER ENTSOE_SVC;   -- RSA_PUBLIC_KEY_FP should start with SHA256:
```

### S3 access

Snowflake reads the bucket by assuming an IAM role. The role can only list and read `raw/file_library/` ([iam/snowflake-s3-policy.json](iam/snowflake-s3-policy.json)). Its trust ([iam/snowflake-s3-trust.json](iam/snowflake-s3-trust.json)) lets in only your Snowflake integration, identified by an AWS user ARN and an external ID that Snowflake shows only after the integration exists. So the setup goes back and forth:

1. Create the role with a temporary trust (your own account, a dummy external ID):

   ```powershell
   (Get-Content infra/iam/snowflake-s3-trust.json -Raw) -replace '<SNOWFLAKE_IAM_USER_ARN>', "arn:aws:iam::${AccountId}:root" -replace '<SNOWFLAKE_EXTERNAL_ID>', '0000' | Set-Content "$env:TEMP\snowflake-trust.json" -Encoding ascii
   aws iam create-role --role-name entsoe-snowflake-s3 --assume-role-policy-document "file://$env:TEMP\snowflake-trust.json"
   aws iam put-role-policy --role-name entsoe-snowflake-s3 --policy-name snowflake-s3-read --policy-document file://infra/iam/snowflake-s3-policy.json
   ```

2. Run section 5 of `setup.sql` with the role's ARN in place of `<ROLE_ARN>`. From `DESC INTEGRATION ENTSOE_S3`, copy `STORAGE_AWS_IAM_USER_ARN` (ends in `:user/...`, not your role) and `STORAGE_AWS_EXTERNAL_ID`.

3. Replace the temporary trust with Snowflake's identity:

   ```powershell
   $SfUserArn = "<STORAGE_AWS_IAM_USER_ARN>"
   $SfExternalId = "<STORAGE_AWS_EXTERNAL_ID>"
   (Get-Content infra/iam/snowflake-s3-trust.json -Raw) -replace '<SNOWFLAKE_IAM_USER_ARN>', $SfUserArn -replace '<SNOWFLAKE_EXTERNAL_ID>', $SfExternalId | Set-Content "$env:TEMP\snowflake-trust.json" -Encoding ascii
   aws iam update-assume-role-policy --role-name entsoe-snowflake-s3 --policy-document "file://$env:TEMP\snowflake-trust.json"
   Remove-Item "$env:TEMP\snowflake-trust.json"
   ```

4. Run section 6 of `setup.sql`. `LIST @ENTSOE.RAW.FILE_LIBRARY_STAGE;` should show the files. An `sts:AssumeRole` error means the trust doesn't match the integration yet; IAM can also take a few seconds to apply a change.

Don't recreate the integration with `CREATE OR REPLACE`: that generates a new external ID, and step 3 has to be repeated.

### Task failure alerts

A failed Snowflake load emails you through the same SNS topic as the Lambda alarm. It's the same back-and-forth as the S3 access, with a role that can only publish to that topic ([iam/snowflake-sns-policy.json](iam/snowflake-sns-policy.json)) and the same trust template:

```
Task fails ──► ENTSOE_ALERTS (notification integration) ──► IAM role entsoe-snowflake-sns ──► SNS entsoe-pipeline-alerts ──► email
```

1. Create the role with a temporary trust:

   ```powershell
   (Get-Content infra/iam/snowflake-s3-trust.json -Raw) -replace '<SNOWFLAKE_IAM_USER_ARN>', "arn:aws:iam::${AccountId}:root" -replace '<SNOWFLAKE_EXTERNAL_ID>', '0000' | Set-Content "$env:TEMP\snowflake-trust.json" -Encoding ascii
   aws iam create-role --role-name entsoe-snowflake-sns --assume-role-policy-document "file://$env:TEMP\snowflake-trust.json"
   aws iam put-role-policy --role-name entsoe-snowflake-sns --policy-name snowflake-sns-publish --policy-document file://infra/iam/snowflake-sns-policy.json
   ```

2. Run section 9 of `setup.sql` with the topic ARN (`arn:aws:sns:eu-west-1:<account>:entsoe-pipeline-alerts`) and the role ARN in place of the placeholders. From `DESC NOTIFICATION INTEGRATION ENTSOE_ALERTS`, copy `SF_AWS_IAM_USER_ARN` and `SF_AWS_EXTERNAL_ID`.

3. Update the trust as in step 3 of the S3 access, with those two values and `--role-name entsoe-snowflake-sns`.

### Loading the raw tables

Each `raw_*.sql` file creates one `RAW` table: the CSV columns as `VARCHAR` (staging casts them), plus `file_name`, `updated_at` (the revision, from the S3 folder) and `loaded_at`. Run each once.

[snowflake/load_file_library.sql](snowflake/load_file_library.sql) creates the `LOAD_FILE_LIBRARY()` procedure, which holds the `COPY` for every dataset, and the `LOAD_FILE_LIBRARY_DAILY` task, which calls it every day at 07:00 UTC with `ERROR_INTEGRATION = ENTSOE_ALERTS`. Run it after the alerts are set up, because the task refers to the integration. Rerun it after changing the procedure.

```
06:00  EventBridge ──► Lambda ──► S3 raw/file_library/
07:00  Snowflake task ──► LOAD_FILE_LIBRARY() ──► RAW tables (new files only)
```

07:00 leaves room for the Lambda's worst case: 3 attempts of 15 minutes plus the retry waits end by 06:48. `COPY` only loads files it hasn't loaded before, so a file that lands late is loaded the next day, and rerunning the load is safe.

```sql
CALL ENTSOE.RAW.LOAD_FILE_LIBRARY();   -- manual run
SELECT scheduled_time, state, error_message
FROM TABLE(ENTSOE.INFORMATION_SCHEMA.TASK_HISTORY(TASK_NAME => 'LOAD_FILE_LIBRARY_DAILY'))
ORDER BY scheduled_time DESC;          -- recent runs
```

To test the alert, make a task that always fails, run it once, then drop it:

```sql
USE ROLE ENTSOE_SERVICE;
CREATE OR REPLACE TASK ENTSOE.RAW.TEST_ALERT WAREHOUSE = ENTSOE_WH ERROR_INTEGRATION = ENTSOE_ALERTS AS SELECT 1/0;
EXECUTE TASK ENTSOE.RAW.TEST_ALERT;   -- an email should arrive within a few minutes
DROP TASK ENTSOE.RAW.TEST_ALERT;
```

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
