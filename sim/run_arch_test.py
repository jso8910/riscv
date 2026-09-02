#!/usr/bin/env python3
"""Run one ACT ELF on the local SystemVerilog core and emit RVCP-SUMMARY."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


IMEM_START = 0x00000000
IMEM_END = 0x000FFFFF
DMEM_START = 0x00100000
DMEM_END = 0x001FFFFF


def run_checked(cmd: list[str], *, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def iter_verilog_bytes(memh_path: Path):
    addr: int | None = None
    for raw_line in memh_path.read_text().splitlines():
        line = raw_line.split("//", 1)[0].strip()
        if not line:
            continue

        tokens = line.split()
        if tokens[0].startswith("@"):
            addr = int(tokens[0][1:], 16)
            tokens = tokens[1:]

        if addr is None:
            raise ValueError(f"Data before address marker in {memh_path}")

        for token in tokens:
            value = int(token, 16)
            if value > 0xFF:
                raise ValueError(f"Expected byte data, got {token!r} in {memh_path}")
            yield addr, value
            addr += 1


def write_memory_records(records: list[tuple[int, int]], path: Path) -> None:
    with path.open("w") as f:
        for addr, value in records:
            f.write(f"{addr:08X} {value:02X}\n")


def extract_memory_records(combined_memh: Path, memory_path: Path) -> None:
    records: list[tuple[int, int]] = []

    for addr, value in iter_verilog_bytes(combined_memh):
        if IMEM_START <= addr <= IMEM_END or DMEM_START <= addr <= DMEM_END:
            records.append((addr, value))

    write_memory_records(records, memory_path)


def compile_testbench(repo_root: Path, output_vvp: Path) -> bool:
    iverilog = shutil.which("iverilog")
    if iverilog is None:
        print("Error: iverilog not found on PATH")
        return False

    result = run_checked(
        [
            iverilog,
            "-g2012",
            "-Wall",
            "-s",
            "tb_arch_test",
            "-o",
            str(output_vvp),
            "-f",
            "sim/tb_arch_test.f",
        ],
        cwd=repo_root,
    )

    for line in result.stdout.splitlines():
        if "sorry: constant selects in always_* processes are not fully supported" in line:
            continue
        print(line)

    return result.returncode == 0


def test_name_from_elf(elf_path: Path) -> str:
    stem = elf_path.stem
    if stem.endswith(".sig"):
        stem = stem[:-4]
    return f"{stem}.S"


def main() -> int:
    parser = argparse.ArgumentParser(description="Run one ACT ELF on the local RTL core")
    parser.add_argument("--max-cycles", type=int, default=2_000_000)
    parser.add_argument("--objcopy", default="riscv32-unknown-elf-objcopy")
    parser.add_argument("elf", type=Path)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    elf_path = args.elf.resolve()
    test_name = test_name_from_elf(elf_path)

    if not elf_path.exists():
        print(f'RVCP-SUMMARY: TEST FAILED - Test File "{test_name}"')
        print(f"Error: ELF not found: {elf_path}")
        return 1

    objcopy = shutil.which(args.objcopy)
    if objcopy is None:
        print(f'RVCP-SUMMARY: TEST FAILED - Test File "{test_name}"')
        print(f"Error: {args.objcopy} not found on PATH")
        return 1

    vvp = shutil.which("vvp")
    if vvp is None:
        print(f'RVCP-SUMMARY: TEST FAILED - Test File "{test_name}"')
        print("Error: vvp not found on PATH")
        return 1

    with tempfile.TemporaryDirectory(prefix="riscv-arch-test-") as tmp:
        tmp_path = Path(tmp)
        combined_memh = tmp_path / "program.memh"
        memory_records = tmp_path / "program.bytes"
        simv = tmp_path / "tb_arch_test.vvp"

        objcopy_result = run_checked(
            [objcopy, "-O", "verilog", "--verilog-data-width=1", str(elf_path), str(combined_memh)]
        )
        if objcopy_result.returncode != 0:
            print(f'RVCP-SUMMARY: TEST FAILED - Test File "{test_name}"')
            print(objcopy_result.stdout, end="")
            return 1

        try:
            extract_memory_records(combined_memh, memory_records)
        except ValueError as exc:
            print(f'RVCP-SUMMARY: TEST FAILED - Test File "{test_name}"')
            print(f"Error: {exc}")
            return 1

        if not compile_testbench(repo_root, simv):
            print(f'RVCP-SUMMARY: TEST FAILED - Test File "{test_name}"')
            return 1

        sim_result = run_checked(
            [
                vvp,
                str(simv),
                f"+mem={memory_records}",
                f"+max_cycles={args.max_cycles}",
            ],
            cwd=repo_root,
        )
        print(sim_result.stdout, end="")

        passed = "TOHOST PASS" in sim_result.stdout and sim_result.returncode == 0
        failed = "TOHOST FAIL" in sim_result.stdout or "TOHOST UNKNOWN" in sim_result.stdout
        if passed:
            print(f'RVCP-SUMMARY: TEST PASSED - Test File "{test_name}"')
            return 0

        print(f'RVCP-SUMMARY: TEST FAILED - Test File "{test_name}"')
        if failed:
            return 1
        return sim_result.returncode or 1


if __name__ == "__main__":
    sys.exit(main())
