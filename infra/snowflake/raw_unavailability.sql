-- Raw unavailability of production and generation units (UnavailabilityOfProductionAndGenerationUnits_15.1.A_B_C_D_r3.1)
-- One row per outage message version; files are by the month the outage covers, so far-future months exist
USE ROLE ENTSOE_SERVICE;
CREATE TABLE IF NOT EXISTS ENTSOE.RAW.UNAVAILABILITY (
    instance_code VARCHAR,
    version VARCHAR,
    old_version VARCHAR,
    start_outage_utc VARCHAR,
    end_outage_utc VARCHAR,
    start_time_series_utc VARCHAR,
    end_time_series_utc VARCHAR,
    status VARCHAR,
    type VARCHAR,
    area_code VARCHAR,
    area_display_name VARCHAR,
    area_type_code VARCHAR,
    area_map_code VARCHAR,
    asset_code VARCHAR,
    asset_name VARCHAR,
    asset_type VARCHAR,
    production_type VARCHAR,
    available_capacity_mw VARCHAR,
    reason VARCHAR,
    comment VARCHAR,
    version_publication_timestamp_utc VARCHAR,
    update_time_utc VARCHAR,
    file_name VARCHAR,
    updated_at TIMESTAMP_NTZ,
    loaded_at TIMESTAMP_NTZ DEFAULT SYSDATE()
);

-- Load new files (COPY skips files it has already loaded)
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
