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
 * No M-mode or CSRs.
 *
 * Defining this macro as EMPTY overrides ACT's normal
 * machine-mode startup code.
 */
#define RVMODEL_BOOT_TO_MMODE


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
 * tohost is 64 bits, so on RV32 we perform two 32-bit stores.
 */
#define RVMODEL_HALT_PASS                            \
  li x1, 1;                                          \
  la t0, tohost;                                     \
1:                                                   \
  sw x1, 0(t0);                                      \
  sw x0, 4(t0);                                      \
  j 1b;


#define RVMODEL_HALT_FAIL                            \
  li x1, 3;                                          \
  la t0, tohost;                                     \
1:                                                   \
  sw x1, 0(t0);                                      \
  sw x0, 4(t0);                                      \
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