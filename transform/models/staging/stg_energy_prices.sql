-- Day-ahead prices: one row per area, time slot, resolution (and auction), latest revision only.
-- RAW keeps every revision; here only the row from the newest file (updated_at) survives.

with source as (
    select * from {{ source('raw', 'energy_prices') }}
),

latest_revision as (
    select *
    from source
    qualify row_number() over (
        partition by area_code, date_time_utc, resolution_code, contract_type, sequence   -- one group per slot (contract_type and sequence keep separate auctions apart)
        order by updated_at desc                                                          -- newest revision first
    ) = 1

)

select
    try_to_timestamp_ntz(date_time_utc)     as datetime_utc,
    resolution_code,
    area_code,
    area_display_name,
    area_type_code,
    area_map_code,
    contract_type,
    nullif(trim(sequence), '')              as sequence,         -- a single space when there is only one auction
    try_to_number(price_currency_mwh, 12, 4) as price_eur_mwh,
    currency,
    updated_at,                                                  -- revision this row comes from
    file_name
from latest_revision
