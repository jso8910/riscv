#include "riscv_bench.h"

#define BENCH_MAILBOX_ADDR 0x001fffb0UL
#define TOHOST_ADDR         0x001ffff0UL

static volatile bench_mailbox_t *const mailbox =
    (volatile bench_mailbox_t *)BENCH_MAILBOX_ADDR;
static volatile uint64_t *const tohost = (volatile uint64_t *)TOHOST_ADDR;

uint64_t benchmark_read_cycle(void)
{
    uint64_t value;
    __asm__ volatile ("csrr %0, mcycle" : "=r"(value));
    return value;
}

uint64_t benchmark_read_instret(void)
{
    uint64_t value;
    __asm__ volatile ("csrr %0, minstret" : "=r"(value));
    return value;
}

void benchmark_platform_init(void)
{
    mailbox->magic = BENCH_MAILBOX_MAGIC;
    mailbox->start_cycle = 0;
    mailbox->stop_cycle = 0;
    mailbox->start_instret = 0;
    mailbox->stop_instret = 0;
    mailbox->status = 0;
    __asm__ volatile ("" ::: "memory");
}

void benchmark_start(void)
{
    __asm__ volatile ("" ::: "memory");
    mailbox->start_cycle = benchmark_read_cycle();
    mailbox->start_instret = benchmark_read_instret();
    __asm__ volatile ("" ::: "memory");
}

void benchmark_stop(void)
{
    __asm__ volatile ("" ::: "memory");
    mailbox->stop_cycle = benchmark_read_cycle();
    mailbox->stop_instret = benchmark_read_instret();
    __asm__ volatile ("" ::: "memory");
}

void benchmark_complete(int status)
{
    mailbox->status = (uint64_t)(uint32_t)status;
    __asm__ volatile ("" ::: "memory");
    *tohost = status == 0 ? 1 : 3;
    for (;;) {
        __asm__ volatile ("nop");
    }
}

void abort(void)
{
    benchmark_complete(0x7f);
}
