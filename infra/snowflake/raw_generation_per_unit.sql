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
