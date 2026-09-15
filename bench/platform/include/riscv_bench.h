#ifndef RISCV_BENCH_H
#define RISCV_BENCH_H

#include <stdint.h>

#define BENCH_MAILBOX_MAGIC 0x42454e43484d4152ULL /* "BENCHMAR" */

typedef struct {
    volatile uint64_t magic;
    volatile uint64_t start_cycle;
    volatile uint64_t stop_cycle;
    volatile uint64_t start_instret;
    volatile uint64_t stop_instret;
    volatile uint64_t status;
    volatile uint64_t reserved0;
    volatile uint64_t reserved1;
} bench_mailbox_t;

void benchmark_platform_init(void);
void benchmark_start(void);
void benchmark_stop(void);
void benchmark_complete(int status) __attribute__((noreturn));
uint64_t benchmark_read_cycle(void);
uint64_t benchmark_read_instret(void);

#endif
