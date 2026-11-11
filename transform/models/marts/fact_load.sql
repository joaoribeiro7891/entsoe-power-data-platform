-- Actual total load for Portugal and Spain from 2023: one row per area, time slot and resolution (latest revision).
-- Portugal reports hourly, Spain every 15 minutes.

select
    datetime_utc,
    area_code,
    resolution_code,
    total_load_mw
from {{ ref('stg_total_load') }}
where area_map_code in ('PT', 'ES')
  and datetime_utc >= '2023-01-01'
