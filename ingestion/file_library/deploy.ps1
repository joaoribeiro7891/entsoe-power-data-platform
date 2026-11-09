# Builds lambda.zip for the File Library Lambda and deploys it.
#
# Usage (from any folder):
#   .\ingestion\file_library\deploy.ps1              # build and deploy
#   .\ingestion\file_library\deploy.ps1 -BuildOnly   # only build lambda.zip
#
# First-time AWS setup (bucket, credentials, role, function, schedule, alarm): see infra/README.md

param([switch]$BuildOnly)

$ErrorActionPreference = "Stop"

$FunctionName = "entsoe-file-library-ingest"
$Region = "eu-west-1"
$PythonVersion = "3.13"   # must match the Lambda runtime (python3.13)
$Requests = "requests==2.34.2"   # pinned so every build packages the same library versions

$here = $PSScriptRoot
$build = Join-Path $here "build"
$zip = Join-Path $here "lambda.zip"

function Assert-Success($step) {
  if ($LASTEXITCODE -ne 0) { throw "$step failed (exit code $LASTEXITCODE)" }
}

# 1. Fresh build folder with the Linux versions of the libraries (Lambda runs on Linux;
#    charset_normalizer ships compiled code, so Windows versions would fail there).
#    boto3 is left out: the Lambda runtime already includes it.
if (Test-Path $build) { Remove-Item $build -Recurse -Force }
uv pip install $Requests --target $build --python-platform x86_64-manylinux2014 --python-version $PythonVersion --only-binary :all:
Assert-Success "Installing $Requests"

# 2. The handler next to its libraries
Copy-Item (Join-Path $here "handler.py") $build

# 3. Zip the contents of build/ so the files sit at the root of the zip.
#    Python's shutil instead of Compress-Archive: older PowerShell versions write "\" paths, which Lambda can't read.
if (Test-Path $zip) { Remove-Item $zip }
uv run python -c "import shutil, sys; shutil.make_archive(sys.argv[1], 'zip', sys.argv[2])" ($zip -replace '\.zip$', '') $build
Assert-Success "Zipping"
Write-Host ("Built {0} ({1:N1} MB)" -f $zip, ((Get-Item $zip).Length / 1MB))

if ($BuildOnly) { return }

# 4. Upload the new code and wait until Lambda has applied it
aws lambda update-function-code --function-name $FunctionName --zip-file "fileb://$zip" --region $Region --query "CodeSha256" --output text
Assert-Success "Uploading the code"
aws lambda wait function-updated --function-name $FunctionName --region $Region
Assert-Success "Waiting for the update"
Write-Host "Deployed to $FunctionName"
