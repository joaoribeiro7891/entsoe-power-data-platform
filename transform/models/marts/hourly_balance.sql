-- Business question 2: how much of Portugal's (and Spain's) electricity is renewable, month by month?
-- One row per area and UTC hour, with the energy ingredients; shares over longer periods come from summing them.
--
-- MW is power at an instant; a share over time needs energy (MWh = MW × hours).
-- A 15-minute value counts as 1/4 hour, so Spain's 15-minute load lines up with hourly generation.
-- For a month: sum(renewable_generation_mwh) / sum(load_mwh). Never average the hourly shares.

with load_hourly as (

    select
        area_code,
        date_trunc('hour', datetime_utc)                                       as hour_utc,
        sum(total_load_mw * {{ hours_per_slot('resolution_code') }})           as load_mwh
    from {{ ref('fact_load') }}
    group by all

),

generation_hourly as (

    select
        g.area_code,
        date_trunc('hour', g.datetime_utc)                                                    as hour_utc,
        sum(g.actual_generation_mw * {{ hours_per_slot('g.resolution_code') }})               as generation_mwh,
        sum(iff(p.is_renewable, g.actual_generation_mw, 0) * {{ hours_per_slot('g.resolution_code') }}) as renewable_generation_mwh
    from {{ ref('fact_generation_type') }} g
    join {{ ref('dim_production_type') }} p on p.production_type = g.production_type
    group by all

),

balance as (

    select
        coalesce(l.area_code, g.area_code)   as area_code,
        coalesce(l.hour_utc, g.hour_utc)     as hour_utc,
        l.load_mwh,
        g.generation_mwh,
        g.renewable_generation_mwh
    from load_hourly l
    full outer join generation_hourly g     -- keep an hour even if one side is missing; its shares are then NULL
        on g.area_code = l.area_code
       and g.hour_utc = l.hour_utc

)

select
    b.area_code,
    b.hour_utc,
    -- each country's own clock, like price_profile_by_year
    case when a.area_map_code = 'ES' then d.date_madrid            else d.date_lisbon  end   as local_date,
    case when a.area_map_code = 'ES' then month(d.datetime_madrid) else d.month_lisbon end   as local_month,
    case when a.area_map_code = 'ES' then year(d.datetime_madrid)  else d.year_lisbon  end   as local_year,

    b.load_mwh,
    b.generation_mwh,
    b.renewable_generation_mwh,
    b.load_mwh - b.generation_mwh                          as net_imports_mwh,   -- approximate: also holds grid losses and pumping; positive = imported

    b.renewable_generation_mwh / nullif(b.generation_mwh, 0) as renewable_share_of_generation,
    b.renewable_generation_mwh / nullif(b.load_mwh, 0)       as renewable_share_of_load
from balance b
join {{ ref('dim_area') }} a     on a.area_code = b.area_code
join {{ ref('dim_datetime') }} d on d.datetime_utc = b.hour_utc
