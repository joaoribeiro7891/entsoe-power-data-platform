-- SCD Type 2 of each area's day-ahead price resolution: one row per version, with the period it was valid.
-- Built from the facts (every price row carries its resolution), so past versions have their real dates
-- and a future change adds a new row on the next build.
-- valid_to is exclusive (the first slot of the next version); the current version has valid_to = NULL.
--
-- "Gaps and islands": mark each slot where the resolution differs from the slot before (a new version starts),
-- number the versions with a running total of those marks, then take each version's first slot.

with slots as (

    select area_code, datetime_utc, resolution_code
    from {{ ref('fact_price') }}

),

marked as (

    select
        *,
        case when resolution_code = lag(resolution_code) over (partition by area_code order by datetime_utc) then 0 else 1 end as starts_new_version
    from slots

),

numbered as (

    select
        *,
        sum(starts_new_version) over (partition by area_code order by datetime_utc rows unbounded preceding) as version_number
    from marked

),

versions as (

    select
        area_code,
        version_number,
        resolution_code          as price_resolution,
        min(datetime_utc)        as valid_from
    from numbered
    group by all

)

select
    v.area_code,
    a.area_display_name,
    a.area_map_code,
    v.version_number,
    v.price_resolution,
    v.valid_from,
    lead(v.valid_from) over (partition by v.area_code order by v.version_number) as valid_to,
    valid_to is null                                                             as is_current
from versions v
join {{ ref('dim_area') }} a on a.area_code = v.area_code
