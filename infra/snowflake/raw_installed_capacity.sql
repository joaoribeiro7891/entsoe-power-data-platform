-- Raw installed generation capacity per production type (InstalledGenerationCapacityAggregated_14.1.A_r3)
-- Yearly values in a single file (month=all), so there is a year instead of a timestamp
USE ROLE ENTSOE_SERVICE;
CREATE TABLE IF NOT EXISTS ENTSOE.RAW.INSTALLED_CAPACITY (
    year VARCHAR,
    time_zone VARCHAR,
    resolution_code VARCHAR,
    area_code VARCHAR,
    area_display_name VARCHAR,
    area_type_code VARCHAR,
    area_map_code VARCHAR,
    production_type VARCHAR,
    aggregated_installed_capacity_mw VARCHAR,
    update_time_utc VARCHAR,
    file_name VARCHAR,
    updated_at TIMESTAMP_NTZ,
    loaded_at TIMESTAMP_NTZ DEFAULT SYSDATE()
);

-- Load new files (COPY skips files it has already loaded)
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
