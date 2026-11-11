-- Raw actual generation per generation unit (ActualGenerationOutputPerGenerationUnit_16.1.A_r3)
USE ROLE ENTSOE_SERVICE;
CREATE TABLE IF NOT EXISTS ENTSOE.RAW.GENERATION_PER_UNIT (
    date_time_utc VARCHAR,
    resolution_code VARCHAR,
    area_code VARCHAR,
    area_display_name VARCHAR,
    area_type_code VARCHAR,
    area_map_code VARCHAR,
    generation_unit_code VARCHAR,
    generation_unit_name VARCHAR,
    generation_unit_type VARCHAR,
    actual_generation_output_mw VARCHAR,
    actual_consumption_mw VARCHAR,
    update_time_utc VARCHAR,
    file_name VARCHAR,
    updated_at TIMESTAMP_NTZ,
    loaded_at TIMESTAMP_NTZ DEFAULT SYSDATE()
);

-- Load new files (COPY skips files it has already loaded)
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
