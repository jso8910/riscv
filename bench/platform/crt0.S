# Copyright (C) 2024 Embecosm Limited and University of Bristol
# Embedded Benchmark Suite.
# SPDX-License-Identifier: GPL-3.0-or-later

.section ".text.start", "ax"
.globl _start
.type _start, @function
_start:
    la sp, __stack_top
    la gp, __global_pointer$
    la t0, __bss_start
    la t1, __bss_end
1:
    bgeu t0, t1, 2f
    sd zero, 0(t0)
    addi t0, t0, 8
    j 1b
2:
    la t0, benchmark_trap
    csrw mtvec, t0
    li a0, 0
    li a1, 0
    call main
    call benchmark_complete

.globl benchmark_trap
.type benchmark_trap, @function
benchmark_trap:
    li a0, 0x7e
    call benchmark_complete
