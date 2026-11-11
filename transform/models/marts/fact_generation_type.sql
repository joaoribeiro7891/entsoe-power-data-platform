-- Actual generation per production type for Portugal and Spain from 2023:
-- one row per area, time slot, resolution and production type (latest revision).
-- Whether a type is renewable comes from dim_production_type.

select
    datetime_utc,
    area_code,
    resolution_code,
    production_type,
    actual_generation_mw,
    actual_consumption_mw     -- energy drawn by the units (e.g. pumped storage pumping); often empty
from {{ ref('stg_generation_per_type') }}
where area_map_code in ('PT', 'ES')
  and datetime_utc >= '2023-01-01'
