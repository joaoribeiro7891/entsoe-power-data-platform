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
