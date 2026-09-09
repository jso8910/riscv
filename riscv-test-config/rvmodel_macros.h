#ifndef _RVMODEL_MACROS_H
#define _RVMODEL_MACROS_H

/*
 * Create ACT's host communication variables.
 *
 * The linker script places this .tohost section at:
 *
 *   tohost   = 0x001ffff0
 *   fromhost = 0x001ffff8
 */
#define RVMODEL_DATA_SECTION                         \
  .pushsection .tohost,"aw",@progbits;              \
  .balign 8;                                         \
  .global tohost;                                    \
tohost:                                              \
  .dword 0;                                          \
  .balign 8;                                         \
  .global fromhost;                                  \
fromhost:                                            \
  .dword 0;                                          \
  .popsection


/*
 * The core implements the standard machine-mode CSR and trap interface, so
 * ACT can use its normal M-mode boot and trap-handler setup.
 */
#define STANDARD_SM_SUPPORTED


/*
 * No DUT-specific startup is necessary.
 */
#define RVMODEL_BOOT


/*
 * ACT convention:
 *
 *   tohost = 1 -> PASS
 *   tohost = 3 -> FAIL
 *
 * tohost is 64 bits, so RV64 can write it atomically.
 */
#define RVMODEL_HALT_PASS                            \
  li x1, 1;                                          \
  la t0, tohost;                                     \
1:                                                   \
  sd x1, 0(t0);                                      \
  j 1b;


#define RVMODEL_HALT_FAIL                            \
  li x1, 3;                                          \
  la t0, tohost;                                     \
1:                                                   \
  sd x1, 0(t0);                                      \
  j 1b;


/*
 * You don't have a UART / console.
 */
#define RVMODEL_IO_INIT(_R1, _R2, _R3)
#define RVMODEL_IO_WRITE_STR(_R1, _R2, _R3, _STR_PTR)

/*
 * Required by the ACT environment.
 *
 * Our DUT has no interrupt mechanism, and unprivileged I tests
 * do not use these.
 */
#define RVMODEL_INTERRUPT_LATENCY 1
#define RVMODEL_TIMER_INT_SOON_DELAY 100

#define RVMODEL_SET_MEXT_INT(_R1, _R2)
#define RVMODEL_CLR_MEXT_INT(_R1, _R2)

#define RVMODEL_SET_MSW_INT(_R1, _R2)
#define RVMODEL_CLR_MSW_INT(_R1, _R2)

#define RVMODEL_SET_SEXT_INT(_R1, _R2)
#define RVMODEL_CLR_SEXT_INT(_R1, _R2)

#define RVMODEL_SET_SSW_INT(_R1, _R2)
#define RVMODEL_CLR_SSW_INT(_R1, _R2)

#endif
