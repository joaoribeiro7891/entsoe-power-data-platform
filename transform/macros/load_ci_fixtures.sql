{#
  CI only: creates the RAW tables in DuckDB from the sample CSVs in ci/fixtures/ (see ci/make_fixtures.py).
  All columns as text, like the Snowflake RAW tables. Runs at the start of every dbt command; does nothing on Snowflake.
#}
{% macro load_ci_fixtures() %}
    {% if target.type == 'duckdb' %}
        {% do run_query("create schema if not exists raw") %}
        {% for table in ['energy_prices', 'total_load', 'generation_per_type', 'physical_flows'] %}
            {% do run_query("create or replace table raw." ~ table ~ " as select * from read_csv('ci/fixtures/" ~ table ~ ".csv', header = true, all_varchar = true)") %}
        {% endfor %}
    {% endif %}
    select 1
{% endmacro %}
