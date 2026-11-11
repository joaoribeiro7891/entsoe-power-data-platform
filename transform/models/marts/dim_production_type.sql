with types as (
  select distinct production_type
  from {{ ref('stg_generation_per_type') }} 
)

select 
  production_type,
  category,
  is_renewable
from types
left join {{ ref('production_type_attributes')}}
using(production_type)