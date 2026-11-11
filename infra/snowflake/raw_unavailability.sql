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
