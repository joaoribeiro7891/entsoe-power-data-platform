-- Day-ahead prices must lie within the European day-ahead market's (SDAC) harmonised price limits.
-- Floor: -500 EUR/MWh until delivery day 2026-05-28, -600 EUR/MWh from 2026-05-29 (NEMO Committee notice, May 2026).
-- Cap: reference +4,000 EUR/MWh (ACER Decision 02/2026), raised automatically in +500 steps when prices near it;
-- +5,000 is used here so a legitimate raised cap doesn't fail the test.
-- A price outside these bounds can't come from the market, so it is a data error.
-- Returns the offending rows; zero rows means the test passes.

select *
from {{ ref('fact_price') }}
where price_eur_mwh < -600
   or price_eur_mwh > 5000
