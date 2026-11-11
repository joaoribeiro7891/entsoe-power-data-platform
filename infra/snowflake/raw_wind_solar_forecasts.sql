-- Raw wind and solar generation forecasts (GenerationForecastsForWindAndSolar_14.1.D_r3)
USE ROLE ENTSOE_SERVICE;
CREATE TABLE IF NOT EXISTS ENTSOE.RAW.WIND_SOLAR_FORECASTS (
    date_time_utc VARCHAR,
    resolution_code VARCHAR,
    area_code VARCHAR,
    area_display_name VARCHAR,
    area_type_code VARCHAR,
    area_map_code VARCHAR,
    production_type VARCHAR,
    day_ahead_generation_forecast_mw VARCHAR,
    intraday_generation_forecast_mw VARCHAR,
    current_generation_forecast_mw VARCHAR,
    update_time_utc VARCHAR,
    file_name VARCHAR,
    updated_at TIMESTAMP_NTZ,
    loaded_at TIMESTAMP_NTZ DEFAULT SYSDATE()
);
