with types as (
  select production_type
  from {{ ref('stg_production_types') }}
)

select 
  production_type,
  category,
  is_renewable
from types
left join {{ ref('production_type_attributes')}}
using(production_type)