-- Cross-border physical flows: one row per direction (out area → in area), time slot and resolution, latest revision only.
-- RAW keeps every revision; here only the row from the newest file (updated_at) survives.

with source as (
    select * from {{ source('raw', 'physical_flows') }}
),

latest_revision as (
    select *
    from source
    qualify row_number() over (
        partition by out_area_code, in_area_code, date_time_utc, resolution_code   -- one group per direction and slot
        order by updated_at desc                                                   -- newest revision first
    ) = 1
)

select
    try_to_timestamp_ntz(date_time_utc)  as datetime_utc,
    resolution_code,
    out_area_code,
    out_area_display_name,
    out_area_type_code,
    out_area_map_code,
    in_area_code,
    in_area_display_name,
    in_area_type_code,
    in_area_map_code,
    try_to_number(flow_mw, 12, 4)        as flow_mw,          -- never negative: the direction is out area → in area
    updated_at,                                               -- revision this row comes from
    file_name
from latest_revision
