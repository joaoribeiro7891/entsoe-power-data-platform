# entsoe-power-data-platform
Batch Data Platform for ENTSO-E electricity market data: AWS ingestion, Snowflake and dbt warehouse, with full revision history.

## Grain of the facts

One row of each fact table is one value for one time slot, after keeping only the **latest revision** (the row from the file with the most recent `updated_at`). Every revision stays in `RAW`; revisions get their own fact in a later step. All times are UTC.

| Fact | One row per | Measures |
|---|---|---|
| `fact_price` | area, time slot, resolution | day-ahead price (EUR/MWh) |
| `fact_load` | area, time slot, resolution | actual total load (MW) |
| `fact_generation_type` | area, time slot, resolution, production type | actual generation and actual consumption (MW) |
| `fact_flow` | out area, in area, time slot, resolution | physical flow (MW) |

- **Resolution is part of the grain.** The same area and day can have 24 hourly or 96 quarter-hourly rows. Day-ahead prices for Portugal and Spain moved from 60 to 15 minutes with the delivery day of 1 October 2025 (last hourly slot 2025-09-30 21:00 UTC).
- **Flows have a direction.** Portugal → Spain and Spain → Portugal are separate rows, each with a non-negative flow.
- **Consumption in generation** is the energy some units draw (pumped storage pumping), so a production type can have both measures.
