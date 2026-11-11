with prices as (
    select area_code, area_display_name, area_map_code, updated_at
    from {{ ref('stg_energy_prices') }}
),

gen_per_type as (
  select area_code, area_display_name, area_map_code, updated_at
  from {{ ref('stg_generation_per_type')}}
),

physical_flows as (
  select 
    in_area_code as area_code, 
    in_area_display_name as area_display_name, 
    in_area_map_code as area_map_code, 
    updated_at
  from {{ ref('stg_physical_flows')}}

  union all

  select
    out_area_code as area_code, 
    out_area_display_name as area_display_name, 
    out_area_map_code as area_map_code, 
    updated_at
  from {{ ref('stg_physical_flows')}}
),


total_loads as (
  select area_code, area_display_name, area_map_code, updated_at
  from {{ ref('stg_total_load')}}
),

all_areas as (
  select * from prices
  union all
  select * from gen_per_type
  union all
  select * from physical_flows
  union all
  select * from total_loads
)

select area_code, area_display_name, area_map_code
from all_areas
qualify row_number() over (partition by area_code order by updated_at desc) = 1