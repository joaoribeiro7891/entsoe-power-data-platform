-- Every local day of every area must have all its day-ahead prices.
-- Instead of counting rows (24, 96, or a mix on the day the resolution changed), add up the hours the slots cover
-- and compare with the length of that local day (23, 24 or 25 hours with DST, taken from dim_datetime).
-- The first and last day of each area are skipped: the data starts and ends at UTC/market-day boundaries,
-- which cut those local days short.
-- Returns the incomplete days; zero rows means the test passes.

with day_lengths as (

    select date_lisbon as local_date, 'PT' as area_map_code, count(*) / 4 as hours_in_day
    from {{ ref('dim_datetime') }}
    group by 1
    union all
    select date_madrid, 'ES', count(*) / 4
    from {{ ref('dim_datetime') }}
    group by 1

),

covered as (

    select
        f.area_code,
        a.area_map_code,
        case when a.area_map_code = 'ES' then d.date_madrid else d.date_lisbon end   as local_date,
        sum({{ hours_per_slot('f.resolution_code') }})                               as hours_covered
    from {{ ref('fact_price') }} f
    join {{ ref('dim_area') }} a     on a.area_code = f.area_code
    join {{ ref('dim_datetime') }} d on d.datetime_utc = f.datetime_utc
    group by all

),

bounded as (

    select
        *,
        min(local_date) over (partition by area_code) as first_day,
        max(local_date) over (partition by area_code) as last_day
    from covered

)

select
    b.area_map_code,
    b.local_date,
    b.hours_covered,
    l.hours_in_day
from bounded b
join day_lengths l
    on l.area_map_code = b.area_map_code
   and l.local_date = b.local_date
where b.local_date > b.first_day
  and b.local_date < b.last_day
  and b.hours_covered <> l.hours_in_day
