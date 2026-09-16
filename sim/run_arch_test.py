#!/usr/bin/env python3
"""Run one ACT ELF on the local SystemVerilog core and emit RVCP-SUMMARY."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


MEM_START = 0x00000000
MEM_END = 0x001FFFFF
# This is also included in the cached-binary signature below.  Setting
# VERILATOR_CFLAGS lets a caller intentionally override it (for example, to
# compare simulator build settings) without reusing an incompatible cache.
VERILATOR_CFLAGS = os.environ.get("VERILATOR_CFLAGS", "-O3")


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
        if MEM_START <= addr <= MEM_END:
            records.append((addr, value))

    write_memory_records(records, memory_path)


def compile_iverilog_testbench(repo_root: Path, output_vvp: Path) -> bool:
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


def filelist_sources(repo_root: Path, filelist: Path, seen: set[Path] | None = None) -> list[Path]:
    """Return HDL sources named by a file list, including nested lists."""
    if seen is None:
        seen = set()
    filelist = filelist.resolve()
    if filelist in seen:
        return []
    seen.add(filelist)

    sources = [filelist]
    for raw_line in filelist.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("//"):
            continue
        if line.startswith("-f "):
            sources.extend(filelist_sources(repo_root, repo_root / line[3:].strip(), seen))
        elif not line.startswith("-"):
            sources.append((repo_root / line).resolve())
    return sources


def verilator_source_signature(repo_root: Path) -> str:
    """Hash all HDL and build-setting inputs so a cached binary is never stale."""
    digest = hashlib.sha256()
    digest.update(b"verilator-arch-test-cache-v2\0")
    digest.update(f"verilator_cflags={VERILATOR_CFLAGS}\0".encode())
    sources = [repo_root / "sim/tb_arch_test.f", repo_root / "tb/tb_arch_test.sv"]
    sources.extend(filelist_sources(repo_root, repo_root / "sim/core_rtl.f"))
    for source in sources:
        digest.update(source.relative_to(repo_root).as_posix().encode())
        digest.update(source.read_bytes())
    return digest.hexdigest()


def compile_verilator_testbench(repo_root: Path, *, rebuild: bool) -> Path | None:
    """Build (or reuse) a process-safe cached Verilator architecture-test binary."""
    verilator = shutil.which("verilator")
    if verilator is None:
        print("Error: verilator not found on PATH")
        return None

    build_root = repo_root / "build"
    build_dir = build_root / "verilator_arch_test"
    binary = build_dir / "Vtb_arch_test"
    signature_file = build_dir / ".source-signature"
    lock_file = build_root / ".verilator_arch_test.lock"
    signature = verilator_source_signature(repo_root)
    build_root.mkdir(exist_ok=True)

    # run_tests.py starts one runner process per ELF. Serialize the first build so
    # all workers subsequently share one known-good executable.
    with lock_file.open("w") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        try:
            if not rebuild and binary.is_file() and signature_file.is_file() and signature_file.read_text() == signature:
                return binary

            build_dir.mkdir(exist_ok=True)
            result = run_checked(
                [
                    verilator,
                    "--binary",
                    "--timing",
                    "-CFLAGS",
                    VERILATOR_CFLAGS,
                    "--top-module",
                    "tb_arch_test",
                    "--Mdir",
                    str(build_dir),
                    "-Wno-TIMESCALEMOD",
                    "-Wno-fatal",
                    "-f",
                    "sim/core_rtl.f",
                    "tb/tb_arch_test.sv",
                ],
                cwd=repo_root,
            )
            print(result.stdout, end="")
            if result.returncode != 0:
                return None
            signature_file.write_text(signature)
            return binary
        finally:
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)


def test_name_from_elf(elf_path: Path) -> str:
    stem = elf_path.stem
    if stem.endswith(".sig"):
        stem = stem[:-4]
    return f"{stem}.S"


def main() -> int:
    parser = argparse.ArgumentParser(description="Run one ACT ELF on the local RTL core")
    parser.add_argument("--max-cycles", type=int, default=2_000_000)
    parser.add_argument("--objcopy", default="riscv64-unknown-elf-objcopy")
    parser.add_argument(
        "--simulator",
        choices=("verilator", "iverilog"),
        default="verilator",
        help="Simulation backend (default: verilator; iverilog is a compatibility fallback)",
    )
    parser.add_argument("--rebuild", action="store_true", help="Rebuild the cached Verilator executable")
    parser.add_argument("--benchmark", action="store_true", help="Enable benchmark mailbox reporting in tb_arch_test")
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

    simulator_binary: Path | str
    if args.simulator == "verilator":
        verilator_binary = compile_verilator_testbench(repo_root, rebuild=args.rebuild)
        if verilator_binary is None:
            print(f'RVCP-SUMMARY: TEST FAILED - Test File "{test_name}"')
            return 1
        simulator_binary = verilator_binary
    else:
        vvp = shutil.which("vvp")
        if vvp is None:
            print(f'RVCP-SUMMARY: TEST FAILED - Test File "{test_name}"')
            print("Error: vvp not found on PATH")
            return 1
        simulator_binary = vvp

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

        if args.simulator == "iverilog":
            if not compile_iverilog_testbench(repo_root, simv):
                print(f'RVCP-SUMMARY: TEST FAILED - Test File "{test_name}"')
                return 1

        sim_result = run_checked(
            [
                str(simulator_binary),
                *([str(simv)] if args.simulator == "iverilog" else []),
                f"+mem={memory_records}",
                f"+max_cycles={args.max_cycles}",
                *(["+benchmark"] if args.benchmark else []),
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
