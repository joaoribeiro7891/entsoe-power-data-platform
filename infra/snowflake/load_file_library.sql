-- Daily load of the File Library CSVs from S3 into ENTSOE.RAW.
-- The tables are created by the raw_*.sql files; the COPYs live only here.
-- COPY skips files it has already loaded, so running this again only loads new files.
USE ROLE ENTSOE_SERVICE;

CREATE OR REPLACE PROCEDURE ENTSOE.RAW.LOAD_FILE_LIBRARY()
  RETURNS VARCHAR
  LANGUAGE SQL
  EXECUTE AS OWNER
AS
$$
BEGIN
    -- energy_prices
    COPY INTO ENTSOE.RAW.ENERGY_PRICES (
        instance_code, date_time_utc, resolution_code, area_code, area_display_name,
        area_type_code, area_map_code, contract_type, sequence, price_currency_mwh,
        currency, update_time_utc, file_name, updated_at
    )
    FROM (
        SELECT
            $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12,
            METADATA$FILENAME,
            TO_TIMESTAMP_NTZ(
                SPLIT_PART(SPLIT_PART(METADATA$FILENAME, 'updated_at=', 2), 'Z', 1),
                'YYYYMMDD"T"HH24MISS'
            )
        FROM @ENTSOE.RAW.FILE_LIBRARY_STAGE/EnergyPrices_12.1.D_r3.1/
    )
    FILE_FORMAT = (FORMAT_NAME = 'ENTSOE.RAW.FILE_LIBRARY_TSV');

    -- total_load
    COPY INTO ENTSOE.RAW.TOTAL_LOAD (
        date_time_utc, resolution_code, area_code, area_display_name, area_type_code,
        area_map_code, total_load_mw, update_time_utc, file_name, updated_at
    )
    FROM (
        SELECT
            $1, $2, $3, $4, $5, $6, $7, $8,
            METADATA$FILENAME,
            TO_TIMESTAMP_NTZ(
                SPLIT_PART(SPLIT_PART(METADATA$FILENAME, 'updated_at=', 2), 'Z', 1),
                'YYYYMMDD"T"HH24MISS'
            )
        FROM @ENTSOE.RAW.FILE_LIBRARY_STAGE/ActualTotalLoad_6.1.A_r3/
    )
    FILE_FORMAT = (FORMAT_NAME = 'ENTSOE.RAW.FILE_LIBRARY_TSV');

    -- generation_per_type
    COPY INTO ENTSOE.RAW.GENERATION_PER_TYPE (
        date_time_utc, resolution_code, area_code, area_display_name, area_type_code,
        area_map_code, production_type, actual_generation_output_mw, actual_consumption_mw,
        update_time_utc, file_name, updated_at
    )
    FROM (
        SELECT
            $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
            METADATA$FILENAME,
            TO_TIMESTAMP_NTZ(
                SPLIT_PART(SPLIT_PART(METADATA$FILENAME, 'updated_at=', 2), 'Z', 1),
                'YYYYMMDD"T"HH24MISS'
            )
        FROM @ENTSOE.RAW.FILE_LIBRARY_STAGE/AggregatedGenerationPerType_16.1.B_C_r3/
    )
    FILE_FORMAT = (FORMAT_NAME = 'ENTSOE.RAW.FILE_LIBRARY_TSV');

    -- generation_per_unit
    COPY INTO ENTSOE.RAW.GENERATION_PER_UNIT (
        date_time_utc, resolution_code, area_code, area_display_name, area_type_code,
        area_map_code, generation_unit_code, generation_unit_name, generation_unit_type,
        actual_generation_output_mw, actual_consumption_mw, update_time_utc, file_name, updated_at
    )
    FROM (
        SELECT
            $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12,
            METADATA$FILENAME,
            TO_TIMESTAMP_NTZ(
                SPLIT_PART(SPLIT_PART(METADATA$FILENAME, 'updated_at=', 2), 'Z', 1),
                'YYYYMMDD"T"HH24MISS'
            )
        FROM @ENTSOE.RAW.FILE_LIBRARY_STAGE/ActualGenerationOutputPerGenerationUnit_16.1.A_r3/
    )
    FILE_FORMAT = (FORMAT_NAME = 'ENTSOE.RAW.FILE_LIBRARY_TSV');

    -- physical_flows
    COPY INTO ENTSOE.RAW.PHYSICAL_FLOWS (
        date_time_utc, resolution_code, out_area_code, out_area_display_name, out_area_type_code,
        out_area_map_code, in_area_code, in_area_display_name, in_area_type_code, in_area_map_code,
        flow_mw, update_time_utc, file_name, updated_at
    )
    FROM (
        SELECT
            $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12,
            METADATA$FILENAME,
            TO_TIMESTAMP_NTZ(
                SPLIT_PART(SPLIT_PART(METADATA$FILENAME, 'updated_at=', 2), 'Z', 1),
                'YYYYMMDD"T"HH24MISS'
            )
        FROM @ENTSOE.RAW.FILE_LIBRARY_STAGE/PhysicalFlows_12.1.G_r3/
    )
    FILE_FORMAT = (FORMAT_NAME = 'ENTSOE.RAW.FILE_LIBRARY_TSV');

    -- wind_solar_forecasts
    COPY INTO ENTSOE.RAW.WIND_SOLAR_FORECASTS (
        date_time_utc, resolution_code, area_code, area_display_name, area_type_code,
        area_map_code, production_type, day_ahead_generation_forecast_mw,
        intraday_generation_forecast_mw, current_generation_forecast_mw,
        update_time_utc, file_name, updated_at
    )
    FROM (
        SELECT
            $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11,
            METADATA$FILENAME,
            TO_TIMESTAMP_NTZ(
                SPLIT_PART(SPLIT_PART(METADATA$FILENAME, 'updated_at=', 2), 'Z', 1),
                'YYYYMMDD"T"HH24MISS'
            )
        FROM @ENTSOE.RAW.FILE_LIBRARY_STAGE/GenerationForecastsForWindAndSolar_14.1.D_r3/
    )
    FILE_FORMAT = (FORMAT_NAME = 'ENTSOE.RAW.FILE_LIBRARY_TSV');

    -- installed_capacity
    COPY INTO ENTSOE.RAW.INSTALLED_CAPACITY (
        year, time_zone, resolution_code, area_code, area_display_name, area_type_code,
        area_map_code, production_type, aggregated_installed_capacity_mw,
        update_time_utc, file_name, updated_at
    )
    FROM (
        SELECT
            $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
            METADATA$FILENAME,
            TO_TIMESTAMP_NTZ(
                SPLIT_PART(SPLIT_PART(METADATA$FILENAME, 'updated_at=', 2), 'Z', 1),
                'YYYYMMDD"T"HH24MISS'
            )
        FROM @ENTSOE.RAW.FILE_LIBRARY_STAGE/InstalledGenerationCapacityAggregated_14.1.A_r3/
    )
    FILE_FORMAT = (FORMAT_NAME = 'ENTSOE.RAW.FILE_LIBRARY_TSV');

    -- unavailability
    COPY INTO ENTSOE.RAW.UNAVAILABILITY (
        instance_code, version, old_version, start_outage_utc, end_outage_utc,
        start_time_series_utc, end_time_series_utc, status, type, area_code,
        area_display_name, area_type_code, area_map_code, asset_code, asset_name,
        asset_type, production_type, available_capacity_mw, reason, comment,
        version_publication_timestamp_utc, update_time_utc, file_name, updated_at
    )
    FROM (
        SELECT
            $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11,
            $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22,
            METADATA$FILENAME,
            TO_TIMESTAMP_NTZ(
                SPLIT_PART(SPLIT_PART(METADATA$FILENAME, 'updated_at=', 2), 'Z', 1),
                'YYYYMMDD"T"HH24MISS'
            )
        FROM @ENTSOE.RAW.FILE_LIBRARY_STAGE/UnavailabilityOfProductionAndGenerationUnits_15.1.A_B_C_D_r3.1/
    )
    FILE_FORMAT = (FORMAT_NAME = 'ENTSOE.RAW.FILE_LIBRARY_TSV');

    RETURN 'File Library load finished';
END;
$$;

-- Runs the load every day at 07:00 UTC: the Lambda starts at 06:00 and, even with
-- two retries after timeouts, is done by 06:48. Files that land later are loaded the next day.
CREATE OR REPLACE TASK ENTSOE.RAW.LOAD_FILE_LIBRARY_DAILY
  WAREHOUSE = ENTSOE_WH
  SCHEDULE = 'USING CRON 0 7 * * * UTC'
  COMMENT = 'Daily COPY of new File Library files into RAW'
AS
  CALL ENTSOE.RAW.LOAD_FILE_LIBRARY();

-- Tasks are created suspended
ALTER TASK ENTSOE.RAW.LOAD_FILE_LIBRARY_DAILY RESUME;

-- Manual run: CALL ENTSOE.RAW.LOAD_FILE_LIBRARY();
-- History:    SELECT * FROM TABLE(ENTSOE.INFORMATION_SCHEMA.TASK_HISTORY(TASK_NAME => 'LOAD_FILE_LIBRARY_DAILY')) ORDER BY SCHEDULED_TIME DESC;