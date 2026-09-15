/* Copyright (C) 2012 Embecosm Limited and University of Bristol

   Contributor: Daniel Torres <dtorres@hmc.edu>

   This file is part of Embench and was formerly part of the Bristol/Embecosm
   Embedded Benchmark Suite.

   SPDX-License-Identifier: GPL-3.0-or-later */

#include <support.h>
#include "riscv_bench.h"

void
initialise_board ()
{
  benchmark_platform_init ();
}

void __attribute__ ((noinline)) __attribute__ ((externally_visible))
start_trigger ()
{
  benchmark_start ();
}

void __attribute__ ((noinline)) __attribute__ ((externally_visible))
stop_trigger ()
{
  benchmark_stop ();
}
