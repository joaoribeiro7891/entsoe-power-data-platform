-- Actual total load: one row per area, time slot and resolution, latest revision only.
-- RAW keeps every revision; here only the row from the newest file (updated_at) survives.

with source as (
    select * from {{ source('raw', 'total_load') }}
),

latest_revision as (
    select *
    from source
    qualify row_number() over (
        partition by area_code, date_time_utc, resolution_code  -- one group per slot
        order by updated_at desc                                -- newest revision first
    ) = 1

)

select
    {{ safe_timestamp('date_time_utc') }}     as datetime_utc,
    resolution_code,
    area_code,
    area_display_name,
    area_type_code,
    area_map_code,
    {{ safe_number('total_load_mw') }} as total_load_mw,
    updated_at,                                                  -- revision this row comes from
    file_name
from latest_revision
