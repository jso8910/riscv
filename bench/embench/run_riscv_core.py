"""Embench target module for the local Verilator RISC-V core model."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from embench_core import log


def get_target_args(remnant):
    parser = argparse.ArgumentParser(description="RISC-V core simulator settings")
    parser.add_argument("--simulator", choices=("verilator", "iverilog"), default="verilator")
    parser.add_argument("--max-cycles", type=int, default=500_000_000)
    return parser.parse_args(remnant)


def run_benchmark(bench, path, args):
    root = Path(__file__).resolve().parents[2]
    command = [
        sys.executable,
        str(root / "sim" / "run_benchmark.py"),
        "--json",
        "--simulator",
        args.simulator,
        "--max-cycles",
        str(args.max_cycles),
        path,
    ]
    try:
        # RV64I builds use compiler helper loops for multiplication and division.
        # The slowest GSF=1 Embench workloads can legitimately take several
        # host minutes under cycle-accurate simulation.
        result = subprocess.run(command, text=True, capture_output=True, timeout=1_200)
    except subprocess.TimeoutExpired:
        log.warning("Warning: %s timed out", bench)
        return None
    if result.returncode != 0:
        log.warning("Warning: %s failed:\n%s", bench, result.stdout)
        return None

    metrics = None
    for line in result.stdout.splitlines():
        if line.startswith("{"):
            metrics = json.loads(line)
    if not metrics or metrics["cycles"] <= 0:
        log.warning("Warning: %s did not return benchmark metrics", bench)
        return None

    elapsed_ms = metrics["cycles"] / (args.cpu_mhz * 1000.0)
    log.debug(
        "%s: cycles=%d instructions=%d elapsed_ms=%.6f",
        bench,
        metrics["cycles"],
        metrics["instructions"],
        elapsed_ms,
    )
    return elapsed_ms
