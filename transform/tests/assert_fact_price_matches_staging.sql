-- fact_price must hold exactly the rows staging has for its scope (Portugal and Spain, day-ahead, from 2023).
-- fact_price is incremental, so this catches a merge that lost or duplicated rows.
-- Returns the areas whose counts differ; zero rows means the test passes.

with source_counts as (

    select area_code, count(*) as source_rows
    from {{ ref('stg_energy_prices') }}
    where area_map_code in ('PT', 'ES')
      and datetime_utc >= '2023-01-01'
      and contract_type = 'Day-ahead'
    group by 1

),

target_counts as (

    select area_code, count(*) as target_rows
    from {{ ref('fact_price') }}
    group by 1

)

select
    coalesce(s.area_code, t.area_code) as area_code,
    s.source_rows,
    t.target_rows
from source_counts s
full outer join target_counts t on t.area_code = s.area_code
where coalesce(s.source_rows, -1) <> coalesce(t.target_rows, -1)
