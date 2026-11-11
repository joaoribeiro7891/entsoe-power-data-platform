-- Day-ahead prices for Portugal and Spain from 2023: one row per area, time slot and resolution (latest revision).
-- Keys point to dim_area and dim_datetime; names and local times come from those dimensions.

select
    datetime_utc,
    area_code,
    resolution_code,
    price_eur_mwh
from {{ ref('stg_energy_prices') }}
where area_map_code in ('PT', 'ES')
    and datetime_utc >= '2023-01-01'
    and contract_type = 'Day-ahead'
