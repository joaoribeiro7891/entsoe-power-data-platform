-- Creating the table to store the raw energy prices data from ENTSOE
USE ROLE ENTSOE_SERVICE;
CREATE TABLE IF NOT EXISTS ENTSOE.RAW.ENERGY_PRICES (
    instance_code VARCHAR,
    date_time_utc VARCHAR,
    resolution_code VARCHAR,
    area_code VARCHAR,
    area_display_name VARCHAR,
    area_type_code VARCHAR,
    area_map_code VARCHAR,
    contract_type VARCHAR,
    sequence VARCHAR,
    price_currency_mwh VARCHAR,
    currency VARCHAR,
    update_time_utc VARCHAR,
    file_name VARCHAR,
    updated_at TIMESTAMP_NTZ,
    loaded_at TIMESTAMP_NTZ DEFAULT SYSDATE()
);


-- Load new files (COPY to skip files already loaded)
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