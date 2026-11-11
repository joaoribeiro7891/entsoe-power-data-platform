-- One row per 15-minute UTC slot, with local time in Lisbon and Madrid.
-- The key is datetime_utc: UTC never repeats or skips, local time does (DST: 23- and 25-hour days).
-- Hourly facts join on the :00 slots.

with minutes as (
    {{ dbt_utils.date_spine(
        datepart="minute",
        start_date="cast('2023-01-01' as timestamp)",
        end_date="cast('2027-01-01' as timestamp)"
    ) }}
),

slots as (
    select date_minute as datetime_utc
    from minutes
    where minute(date_minute) % 15 = 0            -- keep :00, :15, :30, :45
),

local_times as (
    select
        datetime_utc,
        convert_timezone('UTC', 'Europe/Lisbon', datetime_utc) as datetime_lisbon,
        convert_timezone('UTC', 'Europe/Madrid', datetime_utc) as datetime_madrid
    from slots
)

select
    datetime_utc,
    date(datetime_utc)            as date_utc,

    datetime_lisbon,
    date(datetime_lisbon)         as date_lisbon,
    hour(datetime_lisbon)         as hour_lisbon,

    datetime_madrid,
    date(datetime_madrid)         as date_madrid,
    hour(datetime_madrid)         as hour_madrid,

    dayofweekiso(datetime_lisbon) as day_of_week_lisbon, 
    month(datetime_lisbon)        as month_lisbon,
    year(datetime_lisbon)         as year_lisbon
from local_times
