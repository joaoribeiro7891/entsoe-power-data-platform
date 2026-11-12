# entsoe-power-data-platform

Batch data platform for ENTSO-E electricity market data for Portugal and Spain: AWS ingestion, a Snowflake warehouse modelled with dbt, and the full revision history of every source file.

## Architecture

```
ENTSO-E File Library (API)
   │  06:00 UTC daily: Lambda copies new and corrected files (CloudWatch alarm → SNS email on failure)
   ▼
S3  raw/file_library/<dataset>/month=<yyyy_mm>/updated_at=<ts>/<file>.csv   (immutable, versioned)
   │  07:00 UTC daily: Snowflake task runs COPY INTO via a storage integration (failure → same SNS topic)
   ▼
Snowflake  RAW      one table per dataset, every revision, all columns VARCHAR
   │  dbt
   ▼
           STAGING  latest revision per slot, typed (views)
           MARTS    star schema + business-question marts (tables)
```

The File Library keeps only the current version of each file. History exists only because the Lambda snapshots every new version; a correction published and overwritten between two daily runs is not captured.

Setup and operations: [infra/README.md](infra/README.md).

## Data

| Dataset (ENTSO-E) | Scope in the marts |
|---|---|
| Day-ahead prices (12.1.D) | PT, ES |
| Actual total load (6.1.A) | PT, ES |
| Actual generation per production type (16.1.B/C) | PT, ES |
| Cross-border physical flows (12.1.G) | flows to and from PT and ES |

Four more datasets (generation per unit, wind and solar forecasts, installed capacity, unavailability) are ingested into S3 and RAW for later work. Marts cover 2023 onwards; the 2023–2025 history was backfilled once, and daily runs add new and corrected files.

## Model

### Grain of the facts

One row per time slot after keeping the **latest revision** (newest `updated_at`). All times are UTC.

| Fact | One row per | Measures |
|---|---|---|
| `fact_price` | area, time slot, resolution | day-ahead price (EUR/MWh) |
| `fact_load` | area, time slot, resolution | actual total load (MW) |
| `fact_generation_type` | area, time slot, resolution, production type | actual generation, actual consumption (MW) |
| `fact_flow` | out area, in area, time slot, resolution | physical flow (MW) |

- **Resolution is part of the grain.** Day-ahead prices moved from 60 to 15 minutes with delivery day 2025-10-01; PT–ES flows on 2025-05-24. PT load is hourly, ES load quarter-hourly.
- **`fact_price` holds day-ahead prices only.** Spain also publishes intraday auction prices (IDA 1–3) for the same slots since September 2025; they stay in staging.
- **Flows have a direction** and are never negative.
- **Consumption in generation** is mostly pumped storage pumping.

### Dimensions

| Dimension | Key | Notes |
|---|---|---|
| `dim_area` | `area_code` | Union of areas across all four datasets; role-playing in `fact_flow` (out and in area). |
| `dim_area_history` | `area_code`, `valid_from` | SCD Type 2 of the price resolution, derived from the facts (gaps and islands), so past versions have real dates and future changes add rows on the next build. |
| `dim_production_type` | `production_type` | Category and renewable flag from a seed. Pumped storage, nuclear, waste and "Other" are not counted as renewable. |
| `dim_datetime` | `datetime_utc` (15 min) | Local date and hour in Lisbon and Madrid. DST days have 23 or 25 local hours. Ends 2026-12-31. |

### Business-question marts

| Mart | Grain |
|---|---|
| `price_profile_by_year` | area, year, local hour (each country on its own clock) |
| `hourly_balance` | area, UTC hour: load, generation, renewable generation, pumping (MWh), net imports, renewable shares |
| `pt_es_interconnection` | UTC hour: flow in each direction, both prices, price difference, price-split flag |

Energy is computed as MW × slot length, so hourly and quarter-hourly data aggregate together. Shares over a period are `sum / sum`, not averages of hourly shares.

### Incremental and freshness

- `fact_price` is incremental: it filters on the revision timestamp (`updated_at`) and merges on the grain, so corrections to past slots update rows instead of duplicating them. At the current size (≈130k rows) a full rebuild is as fast; the staging view still scans every revision in RAW.
- Source freshness on RAW `loaded_at`: warn after 2 days, error after 3. Installed capacity (yearly) is excluded.

## Findings

**1. Price profile (PT).** Between 2023 and 2025 the midday price halved (13h: 65.8 → 33.4 EUR/MWh) while the evening peak fell 9% (19h: 119.4 → 109.0). The daily spread grew from ≈55 to ≈76 EUR/MWh. In the 13h slot, negative prices first appear in 2024 (minimum −2 EUR/MWh in Spain) and reach −15 in 2025.

**2. Renewables (PT).** Renewables produce 55–81% of generation depending on the month, two thirds to three quarters over a year. Hydro makes rainfall the main driver: 2024 was the highest year (94% of consumption in March 2024). Portugal is a net exporter in wet winters and springs and imports 0.9–1.3 TWh/month in summer.

**3. PT–ES interconnection.** The share of hours with different PT and ES prices rose from 5.3% (2023) to 10.7% (2025) and 14.0% (2026 to November). In most split hours Portugal is the dearer side (imports limited by capacity). The average difference in split hours fell from 22.1 to 2.2 EUR/MWh. Portugal imports about 10 TWh/year net.

**Cross-check.** Net imports from the balance (load + pumping − generation) match the measured PT–ES flows within 0.1% for 2023–2025. Without pumping (3.7 TWh in 2023, 5.4 TWh in 2026 to November) the balance was 4–5 TWh/year short.

## Tests

- **Staging:** unique grain, not null on keys and measures, accepted resolutions.
- **Marts:** unique keys, relationships from every fact to its dimensions, value ranges.
- **Singular:** prices within the SDAC harmonised limits (−600 to +5,000 EUR/MWh); every local day of `fact_price` fully covered (DST-aware); `fact_price` row counts equal staging.

## Cost

| Item | Measured |
|---|---|
| Build day (setup, 7 GB backfill load, all dbt development) | 1.17 credits (X-Small) |
| Daily run (07:00 load task) | TBD |
| Storage, database `ENTSOE` | 1.24 GB |

Warehouse X-Small with 60 s auto-suspend; resource monitor at 30 credits/month (notify at 50% and 80%, suspend at 100%).

## Limitations

- **Recent months not settled.** From June 2026 the balance exceeds the measured flows by up to ≈6%, growing with recency; most likely provisional load and generation data still being revised.
- **Small source gaps.** ES load is missing 150 quarter-hours since 2023; PT–ES 15-minute flows are missing 3.
- **Daily snapshots.** Corrections published and replaced within the same day are not captured.
- **Cross-region reads.** Snowflake runs in eu-west-3 and the bucket in eu-west-1 (≈0.02 USD/GB transferred).
- **Snowflake-specific SQL.** Models use `try_to_number`, `convert_timezone` and `iff`; CI against DuckDB is not set up yet.

## Repository layout

```
ingestion/file_library/   Lambda handler and deploy script
infra/                    IAM policies, Snowflake setup and load SQL, setup guide
transform/                dbt project (models, macros, seeds, tests)
```

## Running dbt

Requires `~/.dbt/profiles.yml` with a Snowflake key-pair profile named `entsoe` (see [infra/README.md](infra/README.md)).

```bash
cd transform
uv run dbt deps
uv run dbt seed
uv run dbt build
uv run dbt source freshness
```
