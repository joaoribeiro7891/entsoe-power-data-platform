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
