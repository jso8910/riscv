#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
embench_dir="$root_dir/third_party/embench-iot"
build_dir=${BUILD_DIR:-"$root_dir/build/bench/embench-speed"}
cc=${CC:-riscv64-unknown-elf-gcc}
ar=${AR:-riscv64-unknown-elf-ar}
gsf=${GSF:-1}
scons=${SCONS:-scons}

if ! command -v "$scons" >/dev/null 2>&1; then
  echo "error: SCons is required; install it and set SCONS=/path/to/scons if it is not on PATH" >&2
  exit 127
fi

common_flags=(
  -std=gnu17 -O2 -ffreestanding -fno-builtin -fno-pic -fno-stack-protector
  -ffunction-sections -fdata-sections -msmall-data-limit=0
  -march=rv64i_zmmul_zicsr_zicntr -mabi=lp64 -mcmodel=medany
  -I"$root_dir/bench/platform/include"
)

platform_dir="$build_dir/platform"
mkdir -p "$platform_dir"
"$cc" "${common_flags[@]}" -c "$root_dir/bench/platform/crt0.S" -o "$platform_dir/crt0.o"
"$cc" "${common_flags[@]}" -c "$root_dir/bench/platform/benchmark.c" -o "$platform_dir/benchmark.o"
"$cc" "${common_flags[@]}" -c "$root_dir/bench/platform/string.c" -o "$platform_dir/string.o"
"$cc" "${common_flags[@]}" -c "$root_dir/bench/platform/softint.c" -o "$platform_dir/softint.o"
"$cc" "${common_flags[@]}" -c "$root_dir/bench/platform/softfloat.c" -o "$platform_dir/softfloat.o"
"$cc" "${common_flags[@]}" -c "$root_dir/bench/platform/ctype.c" -o "$platform_dir/ctype.o"
"$ar" rcs "$platform_dir/libbench_platform.a" "$platform_dir/benchmark.o" "$platform_dir/string.o" "$platform_dir/softint.o" "$platform_dir/softfloat.o" "$platform_dir/ctype.o"

cd "$embench_dir"
"$scons" --config-dir="$root_dir/bench/embench" --build-dir="$build_dir" \
  cc="$cc" \
  cflags="${common_flags[*]}" \
  ldflags="$platform_dir/crt0.o -nostdlib -Wl,--gc-sections -Wl,-T,$root_dir/bench/embench/link.ld -L$platform_dir" \
  user_libs="bench_platform" \
  gsf="$gsf"
