import riscv::*;

module trap_controller(
    input ctrl_t              ctrl_i,
    input logic               hardware_fault_i,
    input logic               csr_illegal_inst_i,
    input logic               address_misaligned_i,

    // PMA
    input logic               pma_instruction_fetch_exception_i,
    input logic               pma_write_exception_i,
    input logic               pma_read_exception_i,
    input [XLEN-1:0]          pma_faulting_addr_i,

    // PMP
    input logic               pmp_write_exception_i,
    input logic               pmp_read_exception_i,
    input logic               pmp_instruction_fetch_exception_i,
    input logic [XLEN-1:0]    pmp_faulting_addr_i,

    // Interrupts
    input logic [XLEN-1:0]    mip_i,
    input logic [XLEN-1:0]    mie_i,
    input logic [XLEN-1:0]    sip_i,
    input logic [XLEN-1:0]    sie_i,
    input logic [XLEN-1:0]    mstatus_i,

    input logic [XLEN-1:0]    mideleg_i,
    input logic [XLEN-1:0]    medeleg_i,

    input machine_privilege_t current_privilege_i,
    input [XLEN-1:0]          pc_i,
    output trap_t             trap_o
);
    logic m_is_interruptible, s_is_interruptible;

    logic [XLEN-1:0] s_ints, m_ints, medeleg_mod;

    // x is interruptible IFF y < x || (y == x) && (xIE == 1)
    assign m_is_interruptible = (current_privilege_i < M_MODE) || ((current_privilege_i == M_MODE) && mstatus_i[MSTATUS_MIE]);
    assign s_is_interruptible = (current_privilege_i < S_MODE) || ((current_privilege_i == S_MODE) && mstatus_i[MSTATUS_SIE]);

    assign m_ints = m_is_interruptible ? mip_i & ~mideleg_i & mie_i : '0;
    assign s_ints = s_is_interruptible ? sip_i & sie_i : '0;

    // The medeleg we use should be all 0s if we are in machine mode
    assign medeleg_mod = current_privilege_i == M_MODE ? '0 : medeleg_i;


    always_comb begin
        trap_o = '0;
        trap_o.is_trap = '0;
        trap_o.is_interrupt = '0;
        trap_o.interrupt_cause = S_SOFTWARE;    // arbitrary
        trap_o.exception_cause = INST_ADDR_MISALIGNED; // arbitrary
        trap_o.dest_machine_privilege = M_MODE;
        trap_o.pc = pc_i;
        trap_o.tval = '0;

        // So far, MTIP and STIP are implemented.
        // Any interrupt bound for machine mode takes priority over any interrupt bound for
        // supervisor mode. Then, the priority order is as follows:
        //  - MEIP > MSIP > MTIP > SEIP > SSIP > STIP
        if (m_ints[M_TIMER]) begin
            trap_o.is_trap = '1;
            trap_o.is_interrupt = '1;
            trap_o.interrupt_cause = M_TIMER;
        end else if (m_ints[S_EXTERNAL]) begin
            trap_o.is_trap = '1;
            trap_o.is_interrupt = '1;
            trap_o.interrupt_cause = S_EXTERNAL;
        end else if (m_ints[S_SOFTWARE]) begin
            trap_o.is_trap = '1;
            trap_o.is_interrupt = '1;
            trap_o.interrupt_cause = S_SOFTWARE;
        end else if (m_ints[S_TIMER]) begin
            trap_o.is_trap = '1;
            trap_o.is_interrupt = '1;
            trap_o.interrupt_cause = S_TIMER;
        end else if (s_ints[S_EXTERNAL]) begin
            trap_o.dest_machine_privilege = S_MODE;
            trap_o.is_trap = '1;
            trap_o.is_interrupt = '1;
            trap_o.interrupt_cause = S_EXTERNAL;
        end else if (s_ints[S_SOFTWARE]) begin
            trap_o.dest_machine_privilege = S_MODE;
            trap_o.is_trap = '1;
            trap_o.is_interrupt = '1;
            trap_o.interrupt_cause = S_SOFTWARE;
        end else if (s_ints[S_TIMER]) begin
            trap_o.dest_machine_privilege = S_MODE;
            trap_o.is_trap = '1;
            trap_o.is_interrupt = '1;
            trap_o.interrupt_cause = S_TIMER;
        end else

        // This ordering implicitly resolves the mcause ordering
        // I have decided that hardware error is top priority of all synchronous traps.
        if (hardware_fault_i) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = HARDWARE_ERROR;

            if (medeleg_mod[HARDWARE_ERROR] && current_privilege_i < M_MODE) begin
                trap_o.dest_machine_privilege = S_MODE;
            end
        end else if (pmp_instruction_fetch_exception_i) begin
            // Note that PMP takes priority over PMA
            trap_o.is_trap = '1;
            trap_o.exception_cause = INST_ACCESS_FAULT;
            trap_o.tval = pmp_faulting_addr_i;

            if (medeleg_mod[INST_ACCESS_FAULT] && current_privilege_i < M_MODE) begin
                trap_o.dest_machine_privilege = S_MODE;
            end
        end else if (pma_instruction_fetch_exception_i) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = INST_ACCESS_FAULT;
            trap_o.tval = pma_faulting_addr_i;

            if (medeleg_mod[INST_ACCESS_FAULT] && current_privilege_i < M_MODE) begin
                trap_o.dest_machine_privilege = S_MODE;
            end
        end else if (address_misaligned_i) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = INST_ADDR_MISALIGNED;

            if (medeleg_mod[INST_ADDR_MISALIGNED] && current_privilege_i < M_MODE) begin
                trap_o.dest_machine_privilege = S_MODE;
            end
        end else if (ctrl_i.illegal || csr_illegal_inst_i) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = ILLEGAL_INSTRUCTION;

            if (medeleg_mod[ILLEGAL_INSTRUCTION] && current_privilege_i < M_MODE) begin
                trap_o.dest_machine_privilege = S_MODE;
            end
        end else if (ctrl_i.ecall && current_privilege_i == M_MODE) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = ECALL_FROM_M_MODE;

            // technically not reachable
            if (medeleg_mod[ECALL_FROM_M_MODE] && current_privilege_i < M_MODE) begin
                trap_o.dest_machine_privilege = S_MODE;
            end
        end else if (ctrl_i.ecall && current_privilege_i == S_MODE) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = ECALL_FROM_S_MODE;

            if (medeleg_mod[ECALL_FROM_S_MODE] && current_privilege_i < M_MODE) begin
                trap_o.dest_machine_privilege = S_MODE;
            end
        end else if (ctrl_i.ecall && current_privilege_i == U_MODE) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = ECALL_FROM_U_MODE;

            if (medeleg_mod[ECALL_FROM_U_MODE] && current_privilege_i < M_MODE) begin
                trap_o.dest_machine_privilege = S_MODE;
            end
        end else if (ctrl_i.ebreak) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = BREAKPOINT;

            if (medeleg_mod[BREAKPOINT] && current_privilege_i < M_MODE) begin
                trap_o.dest_machine_privilege = S_MODE;
            end
        end else if (pmp_write_exception_i) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = STORE_ACCESS_FAULT;
            trap_o.tval = pmp_faulting_addr_i;

            if (medeleg_mod[STORE_ACCESS_FAULT] && current_privilege_i < M_MODE) begin
                trap_o.dest_machine_privilege = S_MODE;
            end
        end else if (pma_write_exception_i) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = STORE_ACCESS_FAULT;
            trap_o.tval = pma_faulting_addr_i;

            if (medeleg_mod[STORE_ACCESS_FAULT] && current_privilege_i < M_MODE) begin
                trap_o.dest_machine_privilege = S_MODE;
            end
        end else if (pmp_read_exception_i) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = LOAD_ACCESS_FAULT;
            trap_o.tval = pmp_faulting_addr_i;

            if (medeleg_mod[LOAD_ACCESS_FAULT] && current_privilege_i < M_MODE) begin
                trap_o.dest_machine_privilege = S_MODE;
            end
        end else if (pma_read_exception_i) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = LOAD_ACCESS_FAULT;
            trap_o.tval = pma_faulting_addr_i;

            if (medeleg_mod[LOAD_ACCESS_FAULT] && current_privilege_i < M_MODE) begin
                trap_o.dest_machine_privilege = S_MODE;
            end
        end
    end
endmodule : trap_controller
