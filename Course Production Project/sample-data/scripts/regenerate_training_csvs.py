#!/usr/bin/env python3
"""Regenerate *_training.csv fixtures from recipes.csv (kitchen stock units)."""

from __future__ import annotations

import csv
import random
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
random.seed(42)


def main() -> None:
    recipes: dict[str, list[tuple[str, float, float]]] = {}
    with (ROOT / "recipes.csv").open() as f:
        for row in csv.DictReader(f):
            recipes.setdefault(row["menuItemId"], []).append(
                (row["sku"], float(row["unitsPerItem"]), float(row["wastageRate"]))
            )

    mix = [
        ("latte", 0.18),
        ("cappuccino", 0.12),
        ("americano", 0.08),
        ("espresso", 0.06),
        ("flat_white", 0.06),
        ("mocha", 0.05),
        ("iced_latte", 0.08),
        ("cold_brew", 0.05),
        ("matcha_latte", 0.04),
        ("chai_latte", 0.04),
        ("english_breakfast", 0.03),
        ("croissant", 0.07),
        ("almond_croissant", 0.04),
        ("blueberry_muffin", 0.03),
        ("chocolate_cookie", 0.03),
        ("avocado_toast", 0.02),
        ("breakfast_sandwich", 0.02),
        ("yogurt_parfait", 0.02),
        ("berry_smoothie", 0.02),
        ("orange_juice", 0.01),
    ]
    total_w = sum(w for _, w in mix)
    mix = [(m, w / total_w) for m, w in mix]

    def pick_item() -> str:
        r = random.random()
        acc = 0.0
        for mid, w in mix:
            acc += w
            if r <= acc:
                return mid
        return mix[-1][0]

    def rush(hour: int) -> float:
        if 7 <= hour <= 9:
            return 1.7
        if 11 <= hour <= 13:
            return 1.45
        if 15 <= hour <= 16:
            return 1.2
        if 17 <= hour <= 18:
            return 1.15
        return 0.65

    start = date(2026, 5, 1)
    days = 90
    hourly_orders: dict[tuple[date, int], int] = {}
    hourly_covers: dict[tuple[date, int], float] = {}
    hourly_reservations: dict[tuple[date, int], int] = {}
    daily_usage: dict[date, dict[str, float]] = {}
    daily_orders: dict[date, int] = {}
    daily_items: dict[date, float] = {}

    for d_i in range(days):
        d = start + timedelta(days=d_i)
        weekend_boost = 1.25 if d.weekday() >= 5 else 1.0
        daily_usage[d] = {}
        daily_orders[d] = 0
        daily_items[d] = 0.0
        for hour in range(7, 20):
            base = random.randint(2, 5)
            n = max(0, int(base * weekend_boost * rush(hour) + random.uniform(-0.5, 0.5)))
            covers = 0.0
            for _ in range(n):
                mid = pick_item()
                qty = 1 if random.random() < 0.7 else 2
                daily_orders[d] += 1
                daily_items[d] += qty
                covers += random.choice([1, 1, 2, 2, 2, 3])
                for sku, units, waste in recipes.get(mid, []):
                    used = qty * units * (1.0 + waste)
                    daily_usage[d][sku] = daily_usage[d].get(sku, 0.0) + used
            rcount = random.randint(0, 2) if hour in (11, 12, 13, 17, 18, 19) else 0
            hourly_reservations[(d, hour)] = rcount
            covers += rcount * 2.5
            hourly_orders[(d, hour)] = n
            hourly_covers[(d, hour)] = covers

    skus = sorted({sku for comps in recipes.values() for sku, _, _ in comps})
    res_cover_map = {
        (d, h): hourly_reservations[(d, h)] * 2.5 for d, h in hourly_reservations
    }

    with (ROOT / "ingredient_daily_training.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(
            [
                "sku",
                "date",
                "year",
                "month",
                "day",
                "weekday",
                "is_weekend",
                "orders_total_lag_1d",
                "items_total_lag_1d",
                "usage_lag_1d",
                "usage_lag_7d",
                "rolling_usage_last_7d",
                "usage_same_weekday_lag_28d",
                "target_usage",
            ]
        )
        for d_i in range(28, days):
            d = start + timedelta(days=d_i)
            py_wd = d.weekday()
            swift_wd = ((py_wd + 1) % 7) + 1
            is_weekend = swift_wd in (1, 7)
            d1 = d - timedelta(days=1)
            d7 = d - timedelta(days=7)
            d28 = d - timedelta(days=28)
            for sku in skus:

                def usage(day: date, sku: str = sku) -> float:
                    return daily_usage.get(day, {}).get(sku, 0.0)

                roll = sum(usage(d - timedelta(days=k)) for k in range(1, 8)) / 7.0
                iso = datetime(d.year, d.month, d.day, tzinfo=timezone.utc).strftime(
                    "%Y-%m-%dT00:00:00Z"
                )
                w.writerow(
                    [
                        sku,
                        iso,
                        d.year,
                        d.month,
                        d.day,
                        swift_wd,
                        str(is_weekend).lower(),
                        daily_orders.get(d1, 0),
                        f"{daily_items.get(d1, 0.0):.4f}",
                        f"{usage(d1):.4f}",
                        f"{usage(d7):.4f}",
                        f"{roll:.4f}",
                        f"{usage(d28):.4f}",
                        f"{usage(d):.4f}",
                    ]
                )

    hours = [
        (start + timedelta(days=di), h) for di in range(days) for h in range(7, 20)
    ]

    def lookup_orders(ts: datetime) -> int:
        if not (7 <= ts.hour <= 19):
            return 0
        return hourly_orders.get((ts.date(), ts.hour), 0)

    def lookup_covers(ts: datetime) -> float:
        if not (7 <= ts.hour <= 19):
            return 0.0
        return hourly_covers.get((ts.date(), ts.hour), 0.0)

    def lookup_res(ts: datetime) -> int:
        if not (7 <= ts.hour <= 19):
            return 0
        return hourly_reservations.get((ts.date(), ts.hour), 0)

    def lookup_res_covers(ts: datetime) -> float:
        if not (7 <= ts.hour <= 19):
            return 0.0
        return res_cover_map.get((ts.date(), ts.hour), 0.0)

    with (ROOT / "orders_hourly_training.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(
            [
                "hour_key",
                "year",
                "month",
                "day",
                "hour",
                "weekday",
                "is_weekend",
                "orders_lag_1h",
                "orders_lag_24h",
                "orders_lag_168h",
                "rolling_orders_24h",
                "covers_lag_1h",
                "covers_lag_24h",
                "target_orders",
            ]
        )
        for idx, (d, h) in enumerate(hours):
            if idx < 168:
                continue
            py_wd = d.weekday()
            swift_wd = ((py_wd + 1) % 7) + 1
            is_weekend = swift_wd in (1, 7)
            dt = datetime(d.year, d.month, d.day, h)
            dt1 = dt - timedelta(hours=1)
            dt24 = dt - timedelta(hours=24)
            dt168 = dt - timedelta(hours=168)
            roll_sum = roll_n = 0
            cursor = dt1
            for _ in range(24):
                if 7 <= cursor.hour <= 19:
                    roll_sum += lookup_orders(cursor)
                    roll_n += 1
                cursor -= timedelta(hours=1)
            roll = (roll_sum / roll_n) if roll_n else 0.0
            w.writerow(
                [
                    f"{d.isoformat()}T{h:02d}",
                    d.year,
                    d.month,
                    d.day,
                    h,
                    swift_wd,
                    str(is_weekend).lower(),
                    lookup_orders(dt1),
                    lookup_orders(dt24),
                    lookup_orders(dt168),
                    f"{roll:.4f}",
                    f"{lookup_covers(dt1):.4f}",
                    f"{lookup_covers(dt24):.4f}",
                    hourly_orders[(d, h)],
                ]
            )

    with (ROOT / "reservations_hourly_training.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(
            [
                "hour_key",
                "year",
                "month",
                "day",
                "hour",
                "weekday",
                "is_weekend",
                "covers_lag_1h",
                "covers_lag_24h",
                "covers_lag_168h",
                "rolling_covers_24h",
                "reservations_lag_1h",
                "reservations_lag_24h",
                "target_covers",
            ]
        )
        for idx, (d, h) in enumerate(hours):
            if idx < 168:
                continue
            py_wd = d.weekday()
            swift_wd = ((py_wd + 1) % 7) + 1
            is_weekend = swift_wd in (1, 7)
            dt = datetime(d.year, d.month, d.day, h)
            dt1 = dt - timedelta(hours=1)
            dt24 = dt - timedelta(hours=24)
            dt168 = dt - timedelta(hours=168)
            roll_sum = 0.0
            roll_n = 0
            cursor = dt1
            for _ in range(24):
                if 7 <= cursor.hour <= 19:
                    roll_sum += lookup_res_covers(cursor)
                    roll_n += 1
                cursor -= timedelta(hours=1)
            roll = (roll_sum / roll_n) if roll_n else 0.0
            w.writerow(
                [
                    f"{d.isoformat()}T{h:02d}",
                    d.year,
                    d.month,
                    d.day,
                    h,
                    swift_wd,
                    str(is_weekend).lower(),
                    f"{lookup_res_covers(dt1):.4f}",
                    f"{lookup_res_covers(dt24):.4f}",
                    f"{lookup_res_covers(dt168):.4f}",
                    f"{roll:.4f}",
                    lookup_res(dt1),
                    lookup_res(dt24),
                    f"{res_cover_map[(d, h)]:.4f}",
                ]
            )

    print("Regenerated training CSVs under", ROOT)


if __name__ == "__main__":
    main()
