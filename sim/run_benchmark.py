#!/usr/bin/env python3
"""Run a bare-metal benchmark ELF and print its mailbox metrics as JSON."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


RESULT_RE = re.compile(
    r"BENCHMARK-RESULT: status=0x(?P<status>[0-9a-fA-F]+) "
    r"start_cycle=0x(?P<start_cycle>[0-9a-fA-F]+) "
    r"stop_cycle=0x(?P<stop_cycle>[0-9a-fA-F]+) "
    r"start_instret=0x(?P<start_instret>[0-9a-fA-F]+) "
    r"stop_instret=0x(?P<stop_instret>[0-9a-fA-F]+)"
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("elf", type=Path)
    parser.add_argument("--max-cycles", type=int, default=20_000_000)
    parser.add_argument("--simulator", choices=("verilator", "iverilog"), default="verilator")
    parser.add_argument("--json", action="store_true", help="emit the parsed metrics as one JSON object")
    parser.add_argument(
        "--coremark-iterations",
        type=int,
        help="also calculate and display CoreMark/MHz for this iteration count",
    )
    parser.add_argument("--rebuild", action="store_true")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    command = [
        sys.executable,
        str(root / "sim" / "run_arch_test.py"),
        "--simulator",
        args.simulator,
        "--max-cycles",
        str(args.max_cycles),
        "--benchmark",
    ]
    if args.rebuild:
        command.append("--rebuild")
    command.append(str(args.elf.resolve()))

    result = subprocess.run(command, cwd=root, text=True, capture_output=True)
    output = result.stdout
    print(output, end="")
    match = RESULT_RE.search(output)
    if result.returncode != 0 or match is None:
        return result.returncode or 1

    metrics = {name: int(value, 16) for name, value in match.groupdict().items()}
    metrics["cycles"] = metrics["stop_cycle"] - metrics["start_cycle"]
    metrics["instructions"] = metrics["stop_instret"] - metrics["start_instret"]
    if metrics["status"] != 0 or metrics["cycles"] <= 0:
        return 1
    if args.coremark_iterations is not None:
        if args.coremark_iterations <= 0:
            parser.error("--coremark-iterations must be positive")
        metrics["coremark_per_mhz"] = args.coremark_iterations * 1_000_000 / metrics["cycles"]
    if args.json:
        print(json.dumps(metrics, sort_keys=True))
    if args.coremark_iterations is not None:
        print(f"CoreMark/MHz: {metrics['coremark_per_mhz']:.6f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
