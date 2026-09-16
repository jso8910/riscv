/*
 * Pipeline dependency and precise-fault regression for the Jason RV64 core.
 *
 * The test uses the normal bare-metal memory map and reports PASS/FAIL through
 * tohost at 0x001ffff0.  It deliberately avoids the ACT signature framework
 * so a failure stops at the exact sub-test rather than being hidden behind a
 * generated test sequence.
 *
 * Coverage:
 *   - load consumers at distances 0, 1, 2, and 3 instructions
 *   - ALU -> MUL, load -> MUL, MUL -> ALU/store/branch consumers
 *   - Sv39 load, store, and instruction page faults with older loads/stores
 *     in flight and younger instructions that must be flushed
 *   - locked NA4 PMP load and instruction-access faults in M mode
 */

    .option norvc

    .equ TOHOST,              0x001ffff0
    .equ VA_UNMAPPED,         0x00400000

    .equ CAUSE_INST_ACCESS,   1
    .equ CAUSE_LOAD_ACCESS,   5
    .equ CAUSE_ECALL_S,       9
    .equ CAUSE_INST_PAGE,     12
    .equ CAUSE_LOAD_PAGE,     13
    .equ CAUSE_STORE_PAGE,    15

    .equ EXP_LOAD_PAGE,       1
    .equ EXP_STORE_PAGE,      2
    .equ EXP_INST_PAGE,       4
    .equ EXP_LOAD_PMP,        8
    .equ EXP_INST_PMP,        16

    /* Keep privileged-state setup out of the dependency micro-tests. */
    .macro CSR_GAP
    addi    x0, x0, 0
    addi    x0, x0, 0
    addi    x0, x0, 0
    addi    x0, x0, 0
    .endm

    .section .text.init, "ax", @progbits
    .globl rvtest_entry_point
rvtest_entry_point:
    la      t0, trap_handler
    csrw    mtvec, t0

    /* Dependency tests run in bare M mode. */
    la      s0, dependency_data

    /* Load-use distances: 0, 1, 2, and 3 independent instructions. */
    ld      t0, 0(s0)
    addi    t1, t0, 1
    li      t2, 42
    bne     t1, t2, fail_load_use_0

    ld      t0, 0(s0)
    addi    x0, x0, 0
    addi    t1, t0, 2
    li      t2, 43
    bne     t1, t2, fail_load_use_1

    ld      t0, 0(s0)
    addi    x0, x0, 0
    addi    x0, x0, 0
    addi    t1, t0, 3
    li      t2, 44
    bne     t1, t2, fail_load_use_2

    ld      t0, 0(s0)
    addi    x0, x0, 0
    addi    x0, x0, 0
    addi    x0, x0, 0
    addi    t1, t0, 4
    li      t2, 45
    bne     t1, t2, fail_load_use_3

    /* Producer forwarding into MUL, then MUL consumers at several distances. */
    li      t0, 6
    addi    t0, t0, 1
    li      t1, 9
    mul     t2, t0, t1                 /* ALU -> MUL, result 63 */
    addi    t3, t2, 1                  /* distance 0 */
    li      t4, 64
    bne     t3, t4, fail_mul_use_0

    mul     t2, t0, t1
    addi    x0, x0, 0
    addi    t3, t2, 2                  /* distance 1 */
    li      t4, 65
    bne     t3, t4, fail_mul_use_1

    mul     t2, t0, t1
    addi    x0, x0, 0
    addi    x0, x0, 0
    addi    t3, t2, 3                  /* distance 2 */
    li      t4, 66
    bne     t3, t4, fail_mul_use_2

    /* A load as a multiply operand and a multiply result as store data. */
    ld      t0, 8(s0)                  /* 11 */
    li      t1, 7
    mul     t2, t0, t1                 /* load -> MUL, result 77 */
    sd      t2, 16(s0)                 /* MUL -> store data */
    ld      t3, 16(s0)
    li      t4, 77
    bne     t3, t4, fail_mul_store

    /* MUL -> branch dependency; the branch must observe the forwarded 63. */
    mul     t2, t0, t1
    li      t3, 77
    beq     t2, t3, mul_branch_ok
    j       fail_mul_branch
mul_branch_ok:

    /* Signed high-half and RV64 MULW result selection. */
    li      t0, -3
    li      t1, 5
    mulh    t2, t0, t1
    li      t3, -1
    bne     t2, t3, fail_mulh
    li      t0, 0x80000000
    li      t1, 2
    mulw    t2, t0, t1
    bne     t2, x0, fail_mulw

    /*
     * Build a minimal Sv39 identity map for virtual 0x00000000..0x001fffff.
     * VA_UNMAPPED is in an unpopulated level-1 entry, so it faults in S mode.
     */
    la      t0, page_root
    la      t1, page_l1
    srli    t1, t1, 12
    slli    t1, t1, 10
    ori     t1, t1, 1                 /* non-leaf valid PTE */
    sd      t1, 0(t0)
    li      t1, 0xcf                  /* V|R|W|X|A|D, 2 MiB leaf at PA 0 */
    la      t0, page_l1
    sd      t1, 0(t0)
    sd      x0, 16(t0)                /* VPN[1] = 2 (VA_UNMAPPED) is invalid */

    la      t0, page_root
    srli    t0, t0, 12
    li      t1, 8
    slli    t1, t1, 60               /* satp.MODE = Sv39 */
    or      t0, t0, t1
    CSR_GAP
    csrw    satp, t0
    CSR_GAP
    sfence.vma x0, x0

    /*
     * An implemented PMP defaults to deny for S/U accesses that do not match
     * an entry.  Allow the 2 MiB RAM image (including the page tables) while
     * retaining entries 0 and 1 for the later, higher-priority deny tests.
     * pmpaddr2 = 0x3ffff encodes a 2 MiB NAPOT range at physical address 0.
     */
    li      t0, 0x3ffff
    CSR_GAP
    csrw    pmpaddr2, t0
    li      t0, 0x1f0000            /* entry 2: R|W|X, NAPOT, unlocked */
    CSR_GAP
    csrw    pmpcfg0, t0
    CSR_GAP

    /* Enter S mode so satp applies to both data accesses and instruction fetch. */
    csrr    t0, mstatus
    li      t1, ~(3 << 11)
    and     t0, t0, t1
    li      t1, (1 << 11)             /* MPP = S */
    or      t0, t0, t1
    CSR_GAP
    csrw    mstatus, t0
    la      t0, s_mode_page_tests
    CSR_GAP
    csrw    mepc, t0
    CSR_GAP
    mret

    .section .text.rvtest, "ax", @progbits
s_mode_page_tests:
    li      s11, 0

    /* Older load must retire when the next load raises a data page fault. */
    la      s0, dependency_data
    ld      s1, 8(s0)
    li      s10, EXP_LOAD_PAGE
    li      s7, 0
    li      t0, VA_UNMAPPED
load_page_fault:
    ld      s7, 0(t0)
    li      s7, 1                    /* younger: must be flushed */
after_load_page_fault:
    li      t1, 11
    bne     s1, t1, fail_old_load_lost
    bne     s7, x0, fail_younger_after_load_pf

    /* Older store must retire; faulting store and younger instruction must not. */
    li      s1, 0x5a
    sd      s1, 24(s0)
    li      s10, EXP_STORE_PAGE
    li      s8, 0
    li      t0, VA_UNMAPPED
store_page_fault:
    sd      s1, 0(t0)
    li      s8, 1                    /* younger: must be flushed */
after_store_page_fault:
    ld      t1, 24(s0)
    bne     t1, s1, fail_old_store_lost
    bne     s8, x0, fail_younger_after_store_pf

    /* An older memory operation must retire before an instruction page fault. */
    ld      s2, 0(s0)
    li      s10, EXP_INST_PAGE
    li      t0, VA_UNMAPPED
instruction_page_fault:
    jalr    x0, 0(t0)
after_instruction_page_fault:
    li      t1, 41
    bne     s2, t1, fail_old_load_before_inst_pf

    li      t0, (EXP_LOAD_PAGE | EXP_STORE_PAGE | EXP_INST_PAGE)
    bne     s11, t0, fail_page_fault_coverage

    /* Return to M mode for locked-PMP tests. */
    ecall

m_after_paging:
    csrw    satp, x0
    CSR_GAP
    sfence.vma x0, x0

    /*
     * Lock two NA4 entries: pmp0 denies execute at pmp_fault_target and
     * pmp1 denies reads at pmp_fault_data. Locked entries apply in M mode.
     */
    la      t0, pmp_fault_target
    srli    t0, t0, 2
    CSR_GAP
    csrw    pmpaddr0, t0
    la      t0, pmp_fault_data
    srli    t0, t0, 2
    CSR_GAP
    csrw    pmpaddr1, t0
    li      t0, 0x9090               /* L=1, A=NA4, R/W/X=0 for entries 0/1 */
    CSR_GAP
    csrw    pmpcfg0, t0
    CSR_GAP

    li      s10, EXP_LOAD_PMP
    li      s7, 0
    la      t0, pmp_fault_data
pmp_load_fault:
    ld      s7, 0(t0)
    li      s7, 1                    /* younger: must be flushed */
after_pmp_load_fault:
    bne     s7, x0, fail_younger_after_pmp_load

    li      s10, EXP_INST_PMP
    la      t0, pmp_fault_target
pmp_instruction_fault:
    jalr    x0, 0(t0)
after_pmp_instruction_fault:
    li      t0, (EXP_LOAD_PMP | EXP_INST_PMP)
    andi    t1, s11, (EXP_LOAD_PMP | EXP_INST_PMP)
    bne     t0, t1, fail_pmp_coverage

pass:
    li      t0, TOHOST
    li      t1, 1
    sd      t1, 0(t0)
1:  j       1b

/*
 * All expected synchronous faults trap to M mode.  Each case verifies cause
 * and tval, marks coverage, and resumes after the faulting instruction.
 */
trap_handler:
    csrr    t0, mcause
    csrr    t1, mtval

    li      t2, CAUSE_LOAD_PAGE
    beq     t0, t2, handle_load_page
    li      t2, CAUSE_STORE_PAGE
    beq     t0, t2, handle_store_page
    li      t2, CAUSE_INST_PAGE
    beq     t0, t2, handle_inst_page
    li      t2, CAUSE_LOAD_ACCESS
    beq     t0, t2, handle_load_pmp
    li      t2, CAUSE_INST_ACCESS
    beq     t0, t2, handle_inst_pmp
    li      t2, CAUSE_ECALL_S
    beq     t0, t2, handle_ecall_s
    j       fail_unexpected_trap

handle_load_page:
    li      t2, EXP_LOAD_PAGE
    bne     s10, t2, fail_wrong_fault
    li      t2, VA_UNMAPPED
    bne     t1, t2, fail_wrong_tval
    or      s11, s11, s10
    la      t2, after_load_page_fault
    CSR_GAP
    csrw    mepc, t2
    CSR_GAP
    mret

handle_store_page:
    li      t2, EXP_STORE_PAGE
    bne     s10, t2, fail_wrong_fault
    li      t2, VA_UNMAPPED
    bne     t1, t2, fail_wrong_tval
    or      s11, s11, s10
    la      t2, after_store_page_fault
    CSR_GAP
    csrw    mepc, t2
    CSR_GAP
    mret

handle_inst_page:
    li      t2, EXP_INST_PAGE
    bne     s10, t2, fail_wrong_fault
    li      t2, VA_UNMAPPED
    bne     t1, t2, fail_wrong_tval
    or      s11, s11, s10
    la      t2, after_instruction_page_fault
    CSR_GAP
    csrw    mepc, t2
    CSR_GAP
    mret

handle_load_pmp:
    li      t2, EXP_LOAD_PMP
    bne     s10, t2, fail_wrong_fault
    la      t2, pmp_fault_data
    bne     t1, t2, fail_wrong_tval
    or      s11, s11, s10
    la      t2, after_pmp_load_fault
    CSR_GAP
    csrw    mepc, t2
    CSR_GAP
    mret

handle_inst_pmp:
    li      t2, EXP_INST_PMP
    bne     s10, t2, fail_wrong_fault
    la      t2, pmp_fault_target
    bne     t1, t2, fail_wrong_tval
    or      s11, s11, s10
    la      t2, after_pmp_instruction_fault
    CSR_GAP
    csrw    mepc, t2
    CSR_GAP
    mret

handle_ecall_s:
    /* mret must return to M mode rather than back to the S-mode ecall. */
    la      t0, m_after_paging
    csrw    mepc, t0
    csrr    t0, mstatus
    li      t1, ~(3 << 11)
    and     t0, t0, t1
    li      t1, (3 << 11)             /* MPP = M */
    or      t0, t0, t1
    CSR_GAP
    csrw    mstatus, t0
    CSR_GAP
    mret

/* Unique labels make a waveform or disassembly immediately identify the sub-test. */
fail_load_use_0:                 li a0, 1;  j fail
fail_load_use_1:                 li a0, 2;  j fail
fail_load_use_2:                 li a0, 3;  j fail
fail_load_use_3:                 li a0, 4;  j fail
fail_mul_use_0:                  li a0, 5;  j fail
fail_mul_use_1:                  li a0, 6;  j fail
fail_mul_use_2:                  li a0, 7;  j fail
fail_mul_store:                  li a0, 8;  j fail
fail_mul_branch:                 li a0, 9;  j fail
fail_mulh:                       li a0, 10; j fail
fail_mulw:                       li a0, 11; j fail
fail_old_load_lost:              li a0, 12; j fail
fail_younger_after_load_pf:      li a0, 13; j fail
fail_old_store_lost:             li a0, 14; j fail
fail_younger_after_store_pf:     li a0, 15; j fail
fail_old_load_before_inst_pf:    li a0, 16; j fail
fail_page_fault_coverage:        li a0, 17; j fail
fail_younger_after_pmp_load:     li a0, 18; j fail
fail_pmp_coverage:               li a0, 19; j fail
fail_unexpected_trap:            li a0, 20; j fail
fail_wrong_fault:                li a0, 21; j fail
fail_wrong_tval:                 li a0, 22; j fail

fail:
    li      t0, TOHOST
    slli    t1, a0, 1
    ori     t1, t1, 1                /* conventional nonzero FAIL value */
    sd      t1, 0(t0)
2:  j       2b

    .balign 4
pmp_fault_target:
    j       fail                       /* must never execute */

    .section .data, "aw", @progbits
    .balign 8
dependency_data:
    .dword 41
    .dword 11
    .dword 0
    .dword 0
    .dword 0

    .balign 8
pmp_fault_data:
    .dword 0x1122334455667788

    .section .bss, "aw", @nobits
    .balign 4096
page_root:
    .skip 4096
    .balign 4096
page_l1:
    .skip 4096

    .section .tohost, "aw", @progbits
    .balign 8
    .globl tohost
tohost:
    .dword 0
