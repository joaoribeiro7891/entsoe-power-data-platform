{#
  Functions that differ between Snowflake (the warehouse) and DuckDB (CI).
  adapter.dispatch picks duckdb__<name> on DuckDB and default__<name> everywhere else.
#}

{# Text to number; NULL instead of an error when the text is not a number #}
{% macro safe_number(column) -%}
    {{ return(adapter.dispatch('safe_number')(column)) }}
{%- endmacro %}

{% macro default__safe_number(column) -%}
    try_to_number({{ column }}, 12, 4)
{%- endmacro %}

{% macro duckdb__safe_number(column) -%}
    try_cast({{ column }} as decimal(12, 4))
{%- endmacro %}


{# Text to timestamp without time zone; NULL instead of an error when the text is not a timestamp #}
{% macro safe_timestamp(column) -%}
    {{ return(adapter.dispatch('safe_timestamp')(column)) }}
{%- endmacro %}

{% macro default__safe_timestamp(column) -%}
    try_to_timestamp_ntz({{ column }})
{%- endmacro %}

{% macro duckdb__safe_timestamp(column) -%}
    try_cast({{ column }} as timestamp)
{%- endmacro %}


{# UTC timestamp (no time zone) to local time in a named zone, DST included #}
{% macro utc_to_local(column, time_zone) -%}
    {{ return(adapter.dispatch('utc_to_local')(column, time_zone)) }}
{%- endmacro %}

{% macro default__utc_to_local(column, time_zone) -%}
    convert_timezone('UTC', '{{ time_zone }}', {{ column }})
{%- endmacro %}

{% macro duckdb__utc_to_local(column, time_zone) -%}
    (({{ column }} at time zone 'UTC') at time zone '{{ time_zone }}')
{%- endmacro %}


{# ISO day of week: 1 = Monday … 7 = Sunday #}
{% macro iso_day_of_week(column) -%}
    {{ return(adapter.dispatch('iso_day_of_week')(column)) }}
{%- endmacro %}

{% macro default__iso_day_of_week(column) -%}
    dayofweekiso({{ column }})
{%- endmacro %}

{% macro duckdb__iso_day_of_week(column) -%}
    isodow({{ column }})
{%- endmacro %}
