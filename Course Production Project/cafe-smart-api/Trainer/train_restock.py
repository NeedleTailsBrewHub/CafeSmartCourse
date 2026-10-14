#!/usr/bin/env python3
"""Train a restock regressor from CafeSmart ingredientDaily CSV and export ONNX."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType, Int64TensorType, StringTensorType
import onnx


NUMERIC_FLOAT = [
    "usage_lag_1d",
    "usage_lag_7d",
    "rolling_usage_last_7d",
    "usage_same_weekday_lag_28d",
    "items_total_lag_1d",
]
NUMERIC_INT = [
    "day",
    "weekday",
    "month",
    "orders_total_lag_1d",
    "year",
]
FEATURE_ORDER = NUMERIC_FLOAT + NUMERIC_INT + ["sku"]
TARGET = "target_usage"
DROP_COLS = {"date", "is_weekend"}


def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Train restock ONNX model")
    p.add_argument("--csv", required=True, help="Path to training CSV")
    p.add_argument("--out", required=True, help="Path to write .onnx")
    return p.parse_args(argv)


def load_frame(csv_path: Path) -> tuple[pd.DataFrame, pd.Series]:
    df = pd.read_csv(csv_path)
    if TARGET not in df.columns:
        raise SystemExit(f"CSV missing target column '{TARGET}'")
    for col in FEATURE_ORDER:
        if col not in df.columns:
            raise SystemExit(f"CSV missing feature column '{col}'")
    y = df[TARGET].astype(float)
    X = df[FEATURE_ORDER].copy()
    for col in NUMERIC_FLOAT:
        X[col] = X[col].astype(float)
    for col in NUMERIC_INT:
        X[col] = X[col].astype(int)
    X["sku"] = X["sku"].astype(str)
    return X, y


def train_and_export(csv_path: Path, out_path: Path) -> None:
    X, y = load_frame(csv_path)
    if len(X) < 5:
        raise SystemExit("Need at least 5 training rows")

    prep = ColumnTransformer(
        transformers=[
            ("num_f", "passthrough", NUMERIC_FLOAT),
            ("num_i", "passthrough", NUMERIC_INT),
            ("sku", OneHotEncoder(handle_unknown="ignore"), ["sku"]),
        ]
    )
    pipe = Pipeline(
        steps=[
            ("prep", prep),
            ("model", HistGradientBoostingRegressor(max_depth=3, max_iter=80)),
        ]
    )
    pipe.fit(X, y)

    initial_types = []
    for col in NUMERIC_FLOAT:
        initial_types.append((col, FloatTensorType([None, 1])))
    for col in NUMERIC_INT:
        initial_types.append((col, Int64TensorType([None, 1])))
    initial_types.append(("sku", StringTensorType([None, 1])))

    onx = convert_sklearn(pipe, initial_types=initial_types, target_opset=15)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("wb") as f:
        f.write(onx.SerializeToString())

    # Validate graph input names for CafeSmart contract
    model = onnx.load(str(out_path))
    names = {i.name for i in model.graph.input}
    missing = [n for n in FEATURE_ORDER if n not in names]
    if missing:
        raise SystemExit(f"ONNX export missing expected inputs: {missing}; got {sorted(names)}")


def main(argv: list[str]) -> int:
    try:
        args = parse_args(argv)
    except SystemExit as e:
        # argparse already printed help
        return int(e.code) if isinstance(e.code, int) else 2
    try:
        train_and_export(Path(args.csv), Path(args.out))
    except SystemExit as e:
        print(str(e), file=sys.stderr)
        return 1
    except Exception as e:  # noqa: BLE001
        print(f"Trainer failed: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
