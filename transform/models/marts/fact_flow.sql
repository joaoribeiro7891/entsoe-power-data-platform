-- Cross-border physical flows to and from Portugal and Spain from 2023:
-- one row per direction (out area → in area), time slot and resolution (latest revision).
-- Both areas point to dim_area (a role-playing dimension). Includes Spain's other borders (France, Morocco, Andorra).

select
    datetime_utc,
    out_area_code,
    in_area_code,
    resolution_code,
    flow_mw                   -- never negative: the direction is out area → in area
from {{ ref('stg_physical_flows') }}
where (out_area_map_code in ('PT', 'ES') or in_area_map_code in ('PT', 'ES'))
  and datetime_utc >= '2023-01-01'
