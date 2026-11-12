-- Every production type that appears in the generation data (Solar, Wind Onshore, Fossil Gas, ...).
-- Reads the RAW column directly, with no latest-revision dedupe: a type's name is the same in every
-- revision, and skipping the dedupe lets Snowflake read one column instead of whole rows.

select distinct production_type
from {{ source('raw', 'generation_per_type') }}
where production_type is not null
