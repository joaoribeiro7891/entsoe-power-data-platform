-- Business question 3: how do flows between Portugal and Spain relate to the price difference between them?
-- One row per UTC hour: energy in each direction, both day-ahead prices and their difference.
--
-- While the interconnection has room, the market equalises the prices (one Iberian price).
-- When it's full (congestion), the prices split, and energy flows from the cheaper side to the dearer one.

with areas as (

    select
        max(case when area_map_code = 'PT' then area_code end) as pt_code,
        max(case when area_map_code = 'ES' then area_code end) as es_code
    from {{ ref('dim_area') }}

),

flows_hourly as (

    select
        date_trunc('hour', f.datetime_utc)                                                              as hour_utc,
        sum(case when f.out_area_code = a.pt_code then f.flow_mw else 0 end * {{ hours_per_slot('f.resolution_code') }}) as flow_pt_to_es_mwh,
        sum(case when f.out_area_code = a.es_code then f.flow_mw else 0 end * {{ hours_per_slot('f.resolution_code') }}) as flow_es_to_pt_mwh
    from {{ ref('fact_flow') }} f
    cross join areas a
    where (f.out_area_code = a.pt_code and f.in_area_code = a.es_code)
       or (f.out_area_code = a.es_code and f.in_area_code = a.pt_code)
    group by all

),

prices_hourly as (

    select
        date_trunc('hour', p.datetime_utc)                         as hour_utc,
        avg(case when p.area_code = a.pt_code then p.price_eur_mwh end)  as price_pt_eur_mwh,   -- 15-minute prices: average of the 4 in the hour
        avg(case when p.area_code = a.es_code then p.price_eur_mwh end)  as price_es_eur_mwh
    from {{ ref('fact_price') }} p
    cross join areas a
    group by all

)

select
    p.hour_utc,
    d.date_lisbon,
    d.hour_lisbon,
    d.year_lisbon,

    f.flow_pt_to_es_mwh,
    f.flow_es_to_pt_mwh,
    f.flow_es_to_pt_mwh - f.flow_pt_to_es_mwh                     as net_flow_to_pt_mwh,   -- positive = Portugal imported

    p.price_pt_eur_mwh,
    p.price_es_eur_mwh,
    p.price_pt_eur_mwh - p.price_es_eur_mwh                       as price_diff_eur_mwh,   -- positive = Portugal dearer
    abs(p.price_pt_eur_mwh - p.price_es_eur_mwh) >= 0.01          as is_price_split        -- the interconnection was full for at least part of the hour
from prices_hourly p
left join flows_hourly f        on f.hour_utc = p.hour_utc   -- keep the hour even if flows are missing
join {{ ref('dim_datetime') }} d on d.datetime_utc = p.hour_utc
