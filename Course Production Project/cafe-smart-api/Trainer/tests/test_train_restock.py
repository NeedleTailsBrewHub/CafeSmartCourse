import subprocess
import sys
from pathlib import Path

import onnx
import pytest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "train_restock.py"
FIXTURE = ROOT / "fixtures" / "restock_tiny.csv"


def run_cli(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
    )


def test_cli_requires_csv_and_out():
    proc = run_cli([])
    assert proc.returncode != 0


def test_trains_fixture_csv_writes_onnx(tmp_path: Path):
    out = tmp_path / "model.onnx"
    proc = run_cli(["--csv", str(FIXTURE), "--out", str(out)])
    assert proc.returncode == 0, proc.stderr
    assert out.exists() and out.stat().st_size > 0
    onnx.load(str(out))


def test_onnx_input_names_match_contract(tmp_path: Path):
    out = tmp_path / "model.onnx"
    proc = run_cli(["--csv", str(FIXTURE), "--out", str(out)])
    assert proc.returncode == 0, proc.stderr
    model = onnx.load(str(out))
    names = {i.name for i in model.graph.input}
    for required in [
        "sku",
        "usage_lag_1d",
        "usage_lag_7d",
        "day",
        "weekday",
        "month",
        "year",
        "orders_total_lag_1d",
        "items_total_lag_1d",
        "rolling_usage_last_7d",
        "usage_same_weekday_lag_28d",
    ]:
        assert required in names, f"missing {required} in {names}"


def test_bad_csv_fails_nonzero(tmp_path: Path):
    bad = tmp_path / "bad.csv"
    bad.write_text("foo,bar\n1,2\n", encoding="utf-8")
    out = tmp_path / "model.onnx"
    proc = run_cli(["--csv", str(bad), "--out", str(out)])
    assert proc.returncode != 0
    assert proc.stderr.strip()
    assert not out.exists()
