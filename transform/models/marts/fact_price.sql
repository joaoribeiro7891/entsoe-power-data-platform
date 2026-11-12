-- Day-ahead prices for Portugal and Spain from 2023: one row per area, time slot and resolution (latest revision).
-- Keys point to dim_area and dim_datetime; names and local times come from those dimensions.
--
-- Incremental: each run only processes rows whose revision (updated_at) is new since the last run,
-- and merges them on the grain. A correction to an old slot updates that row; a new slot is inserted.
-- Filtering on datetime_utc instead would miss corrections to slots already in the table.
-- Strategy: merge on Snowflake; delete+insert on DuckDB (CI).

{{
    config(
        materialized='incremental',
        unique_key=['area_code', 'datetime_utc', 'resolution_code'],
        incremental_strategy=('merge' if target.type == 'snowflake' else 'delete+insert'),
        on_schema_change='append_new_columns'
    )
}}

select
    datetime_utc,
    area_code,
    resolution_code,
    price_eur_mwh,
    updated_at                -- revision this row comes from; drives the incremental filter
from {{ ref('stg_energy_prices') }}
where area_map_code in ('PT', 'ES')
    and datetime_utc >= '2023-01-01'
    and contract_type = 'Day-ahead'

{% if is_incremental() %}
    -- >= rather than >: re-merging rows from the last revision is harmless, missing one is not
    and updated_at >= (select max(updated_at) from {{ this }})
{% endif %}
