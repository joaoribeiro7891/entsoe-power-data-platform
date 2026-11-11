-- Actual generation per production type: one row per area, time slot, resolution and production type, latest revision only.
-- RAW keeps every revision; here only the row from the newest file (updated_at) survives.

with source as (
    select * from {{ source('raw', 'generation_per_type') }}
),

latest_revision as (
    select *
    from source
    qualify row_number() over (
        partition by area_code, date_time_utc, resolution_code, production_type   -- one group per slot and production type
        order by updated_at desc                                                  -- newest revision first
    ) = 1
)

select
    try_to_timestamp_ntz(date_time_utc)               as datetime_utc,
    resolution_code,
    area_code,
    area_display_name,
    area_type_code,
    area_map_code,
    production_type,
    try_to_number(actual_generation_output_mw, 12, 4) as actual_generation_mw,
    try_to_number(actual_consumption_mw, 12, 4)       as actual_consumption_mw,   -- energy drawn by the units (e.g. pumped storage pumping); often empty
    updated_at,                                                                   -- revision this row comes from
    file_name
from latest_revision
