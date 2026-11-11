{#
  How many hours one time slot lasts, from its ENTSO-E resolution code.
  Multiply a MW value by this to get the energy of that slot in MWh.
#}
{% macro hours_per_slot(resolution_column) -%}
    case {{ resolution_column }}
        when 'PT15M' then 0.25
        when 'PT30M' then 0.5
        when 'PT60M' then 1
    end
{%- endmacro %}
