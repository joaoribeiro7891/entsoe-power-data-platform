USE ROLE SYSADMIN;

-- 1. creating the warehouse
CREATE WAREHOUSE IF NOT EXISTS ENTSOE_WH
  WITH WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

-- 2. Database and layers
CREATE DATABASE IF NOT EXISTS ENTSOE;

CREATE SCHEMA IF NOT EXISTS ENTSOE.RAW;       -- data exactly as loaded from S3
CREATE SCHEMA IF NOT EXISTS ENTSOE.STAGING;   -- dbt: 1:1 with the source, renamed and typed, no joins
CREATE SCHEMA IF NOT EXISTS ENTSOE.MARTS;     -- dbt: star schema with facts and dimensions


-- 3. Creating a resource monitor to limit the monthly credit usage of the account. The monitor will send notifications at 50% and 80% of the quota, and will suspend warehouses at 100% and 110% of the quota.
USE ROLE ACCOUNTADMIN;

CREATE RESOURCE MONITOR IF NOT EXISTS ENTSOE_MONITOR
  WITH CREDIT_QUOTA = 30           
  FREQUENCY = MONTHLY
  START_TIMESTAMP = IMMEDIATELY
  TRIGGERS
    ON 50 PERCENT DO NOTIFY         -- email at 15 credits
    ON 80 PERCENT DO NOTIFY         -- email at 24 credits
    ON 100 PERCENT DO SUSPEND       -- stop warehouses; running queries may finish
    ON 110 PERCENT DO SUSPEND_IMMEDIATE;   -- safety net: cancel running queries too

-- Account level
ALTER ACCOUNT SET RESOURCE_MONITOR = ENTSOE_MONITOR;


-- 4. Roles created by USERADMIN
USE ROLE USERADMIN;
CREATE ROLE IF NOT EXISTS ENTSOE_SERVICE;

-- Grants managed by SECURITYADMIN
USE ROLE SECURITYADMIN;
GRANT ROLE ENTSOE_SERVICE TO ROLE SYSADMIN;   -- SYSADMIN sits above every custom role, so it can manage what this role creates

-- Compute and database
GRANT USAGE ON WAREHOUSE ENTSOE_WH TO ROLE ENTSOE_SERVICE;
GRANT USAGE ON DATABASE ENTSOE TO ROLE ENTSOE_SERVICE;

-- RAW: create tables and load into them (COPY INTO), read them for dbt
GRANT USAGE, CREATE TABLE ON SCHEMA ENTSOE.RAW TO ROLE ENTSOE_SERVICE;

-- STAGING and MARTS: dbt creates and owns its own tables and views here
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA ENTSOE.STAGING TO ROLE ENTSOE_SERVICE;
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA ENTSOE.MARTS TO ROLE ENTSOE_SERVICE;


-- Service user for dbt and the loads
USE ROLE USERADMIN;

CREATE USER IF NOT EXISTS ENTSOE_SVC
  TYPE = SERVICE
  DEFAULT_ROLE = ENTSOE_SERVICE
  DEFAULT_WAREHOUSE = ENTSOE_WH
  COMMENT = 'dbt and loads; key-pair authentication only';

USE ROLE SECURITYADMIN;
GRANT ROLE ENTSOE_SERVICE TO USER ENTSOE_SVC;




-- 5. S3 acccess: storage integration
USE ROLE ACCOUNTADMIN;
CREATE STORAGE INTEGRATION IF NOT EXISTS ENTSOE_S3
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = '<ROLE_ARN>'   -- to run with the real ARN in the worksheet only
  STORAGE_ALLOWED_LOCATIONS = ('s3://entsoe-power-raw-joaoribeiro/raw/file_library/');

GRANT USAGE ON INTEGRATION ENTSOE_S3 TO ROLE SYSADMIN;
DESC INTEGRATION ENTSOE_S3;


-- 6. External stage on the raw files
USE ROLE SYSADMIN;
CREATE STAGE IF NOT EXISTS ENTSOE.RAW.FILE_LIBRARY_STAGE
  STORAGE_INTEGRATION = ENTSOE_S3
  URL = 's3://entsoe-power-raw-joaoribeiro/raw/file_library/';

USE ROLE SECURITYADMIN;
GRANT USAGE ON STAGE ENTSOE.RAW.FILE_LIBRARY_STAGE TO ROLE ENTSOE_SERVICE;

-- test: list your CSVs
USE ROLE SYSADMIN;
LIST @ENTSOE.RAW.FILE_LIBRARY_STAGE;