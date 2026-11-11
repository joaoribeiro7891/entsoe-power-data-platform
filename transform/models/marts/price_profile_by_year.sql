-- Business question 1: what does the daily price curve look like in Portugal and Spain, and how has it changed since 2023?
-- One row per area, year and local hour: the average day-ahead price at that hour of the day, over the whole year.
-- Each country uses its own clock (Spain is one hour ahead of Portugal), so a curve never shifts by an hour.

with prices as (

    select
        a.area_code,
        a.area_map_code,
        a.area_display_name,
        case when a.area_map_code = 'ES' then year(d.datetime_madrid) else d.year_lisbon end   as year,
        case when a.area_map_code = 'ES' then d.hour_madrid           else d.hour_lisbon end   as local_hour,
        f.price_eur_mwh
    from {{ ref('fact_price') }} f
    join {{ ref('dim_area') }} a     on a.area_code = f.area_code
    join {{ ref('dim_datetime') }} d on d.datetime_utc = f.datetime_utc

)

select
    area_code,
    area_map_code,
    area_display_name,
    year,
    local_hour,
    round(avg(price_eur_mwh), 2)  as avg_price_eur_mwh,
    min(price_eur_mwh)            as min_price_eur_mwh,
    max(price_eur_mwh)            as max_price_eur_mwh,
    count(*)                      as price_count          -- 15-minute years have 4 prices per hour
from prices
group by all
