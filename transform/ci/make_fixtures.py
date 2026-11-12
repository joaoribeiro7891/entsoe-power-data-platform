"""
Generates the sample RAW data that CI loads into DuckDB (transform/ci/fixtures/*.csv).

Not real ENTSO-E data: four days of plausible values for Portugal and Spain, with the same
columns as the Snowflake RAW tables, plus the edge cases the models must handle:
  - an older revision of every price on 2024-05-02 (the latest-revision dedupe must remove it)
  - Spanish intraday prices on 2024-05-03 (fact_price must keep day-ahead only)
  - Portuguese load hourly, Spanish load every 15 minutes (MW to MWh conversion)
  - pumped storage with consumption at midday (hourly_balance pumping)
  - a few hours where the PT and ES prices differ (pt_es_interconnection price split)

Run from transform/:  uv run python ci/make_fixtures.py
"""

import csv
import math
import os
from datetime import datetime, timedelta

OUT = os.path.join(os.path.dirname(__file__), "fixtures")
START = datetime(2024, 5, 1)          # UTC; 4 full days, so every local day but the first and last is complete
HOURS = 4 * 24
LATEST = "2024-05-05 06:00:00"        # updated_at of the current revision
OLDER = "2024-05-01 12:00:00"         # updated_at of the superseded revision
LOADED = "2024-05-05 07:00:00"

AREAS = {
    "PT": {"code": "10YPT-REN------W", "name": "Portugal (PT)"},
    "ES": {"code": "10YES-REE------0", "name": "Spain (ES)"},
}
AREA_TYPE = "BZN/CTA/CTY"


def ts(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%d %H:%M:%S")


def file_name(folder: str, updated_at: str) -> str:
    stamp = updated_at.replace("-", "").replace(":", "").replace(" ", "T") + "Z"
    return f"{folder}/month=2024_05/updated_at={stamp}/2024_05_{folder}.csv"


def area_cols(key: str) -> list[str]:
    a = AREAS[key]
    return [a["code"], a["name"], AREA_TYPE, key]


def write(name: str, header: list[str], rows: list[list]) -> None:
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, f"{name}.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    print(f"{name}.csv: {len(rows)} rows")


def price(hour_of_day: int) -> float:
    # duck curve: cheap midday, expensive evening
    return round(70 - 40 * math.exp(-((hour_of_day - 13) ** 2) / 8) + 40 * math.exp(-((hour_of_day - 20) ** 2) / 4), 2)


def prices() -> None:
    folder = "EnergyPrices_12.1.D_r3.1"
    header = ["instance_code", "date_time_utc", "resolution_code", "area_code", "area_display_name", "area_type_code",
              "area_map_code", "contract_type", "sequence", "price_currency_mwh", "currency", "update_time_utc",
              "file_name", "updated_at", "loaded_at"]
    rows = []
    for h in range(HOURS):
        dt = START + timedelta(hours=h)
        base = price(dt.hour)
        for key in AREAS:
            p = base + (12.5 if key == "PT" and dt.hour in (19, 20) else 0)    # price split: PT dearer in the evening peak
            rows.append(["fixture", ts(dt), "PT60M", *area_cols(key), "Day-ahead", " ", f"{p:.2f}", "EUR",
                         LATEST, file_name(folder, LATEST), LATEST, LOADED])
            if dt.date() == datetime(2024, 5, 2).date():                        # superseded revision
                rows.append(["fixture", ts(dt), "PT60M", *area_cols(key), "Day-ahead", " ", f"{p + 5:.2f}", "EUR",
                             OLDER, file_name(folder, OLDER), OLDER, LOADED])
        if dt.date() == datetime(2024, 5, 3).date():                            # Spanish intraday auction
            rows.append(["fixture", ts(dt), "PT60M", *area_cols("ES"), "Intraday", "1", f"{base - 3:.2f}", "EUR",
                         LATEST, file_name(folder, LATEST), LATEST, LOADED])
    write("energy_prices", header, rows)


def total_load() -> None:
    folder = "ActualTotalLoad_6.1.A_r3"
    header = ["date_time_utc", "resolution_code", "area_code", "area_display_name", "area_type_code", "area_map_code",
              "total_load_mw", "update_time_utc", "file_name", "updated_at", "loaded_at"]
    rows = []
    for h in range(HOURS):
        dt = START + timedelta(hours=h)
        shape = 1 + 0.15 * math.sin((dt.hour - 7) / 24 * 2 * math.pi)
        rows.append([ts(dt), "PT60M", *area_cols("PT"), f"{5200 * shape:.3f}", LATEST, file_name(folder, LATEST), LATEST, LOADED])
        for q in range(4):                                                      # Spain: every 15 minutes
            rows.append([ts(dt + timedelta(minutes=15 * q)), "PT15M", *area_cols("ES"), f"{28000 * shape:.3f}",
                         LATEST, file_name(folder, LATEST), LATEST, LOADED])
    write("total_load", header, rows)


def generation_per_type() -> None:
    folder = "AggregatedGenerationPerType_16.1.B_C_r3"
    header = ["date_time_utc", "resolution_code", "area_code", "area_display_name", "area_type_code", "area_map_code",
              "production_type", "actual_generation_output_mw", "actual_consumption_mw", "update_time_utc",
              "file_name", "updated_at", "loaded_at"]
    scale = {"PT": 1, "ES": 5}
    rows = []
    for h in range(HOURS):
        dt = START + timedelta(hours=h)
        sun = max(0.0, math.sin((dt.hour - 6) / 14 * math.pi)) if 6 <= dt.hour <= 20 else 0.0
        for key in AREAS:
            s = scale[key]
            values = {
                "Solar": (2500 * sun * s, ""),
                "Wind Onshore": (1500 * s, ""),
                "Fossil Gas": (max(300.0, 1800 - 1500 * sun) * s, ""),
                "Hydro Pumped Storage": (0 if 10 <= dt.hour <= 15 else 400 * s, f"{600 * s:.3f}" if 10 <= dt.hour <= 15 else ""),
            }
            for production_type, (gen, cons) in values.items():
                rows.append([ts(dt), "PT60M", *area_cols(key), production_type, f"{gen:.3f}", cons,
                             LATEST, file_name(folder, LATEST), LATEST, LOADED])
    write("generation_per_type", header, rows)


def physical_flows() -> None:
    folder = "PhysicalFlows_12.1.G_r3"
    header = ["date_time_utc", "resolution_code", "out_area_code", "out_area_display_name", "out_area_type_code",
              "out_area_map_code", "in_area_code", "in_area_display_name", "in_area_type_code", "in_area_map_code",
              "flow_mw", "update_time_utc", "file_name", "updated_at", "loaded_at"]
    rows = []
    for h in range(HOURS):
        dt = START + timedelta(hours=h)
        es_to_pt = 2000 if 9 <= dt.hour <= 21 else 400         # Portugal imports Spanish solar during the day
        for out_key, in_key, flow in (("ES", "PT", es_to_pt), ("PT", "ES", 0)):
            rows.append([ts(dt), "PT60M", *area_cols(out_key), *area_cols(in_key), f"{flow:.3f}",
                         LATEST, file_name(folder, LATEST), LATEST, LOADED])
    write("physical_flows", header, rows)


if __name__ == "__main__":
    prices()
    total_load()
    generation_per_type()
    physical_flows()
