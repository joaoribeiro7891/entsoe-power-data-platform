-- Raw cross-border physical flows (PhysicalFlows_12.1.G_r3), from the out area to the in area
USE ROLE ENTSOE_SERVICE;
CREATE TABLE IF NOT EXISTS ENTSOE.RAW.PHYSICAL_FLOWS (
    date_time_utc VARCHAR,
    resolution_code VARCHAR,
    out_area_code VARCHAR,
    out_area_display_name VARCHAR,
    out_area_type_code VARCHAR,
    out_area_map_code VARCHAR,
    in_area_code VARCHAR,
    in_area_display_name VARCHAR,
    in_area_type_code VARCHAR,
    in_area_map_code VARCHAR,
    flow_mw VARCHAR,
    update_time_utc VARCHAR,
    file_name VARCHAR,
    updated_at TIMESTAMP_NTZ,
    loaded_at TIMESTAMP_NTZ DEFAULT SYSDATE()
);

-- Load new files (COPY skips files it has already loaded)
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
