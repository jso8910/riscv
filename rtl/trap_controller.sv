import riscv::*;

module trap_controller(
    input ctrl_t              ctrl_i,
    input logic               hardware_fault_i,
    input logic               csr_illegal_inst_i,
    input logic               address_misaligned_i,

    // Memory faults
    input mem_fault_t [MEM_READ_PORTS-1:0]     mem_fault_i,
    input logic [MEM_READ_PORTS-1:0][XLEN-1:0] mem_fault_addr_i,
    input logic                                load_page_fault_i,
    input logic                                store_page_fault_i,
    input logic                                fetch_page_fault_i,
    input logic [XLEN-1:0]                     page_fault_addr_i,

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
    logic m_is_interruptible, s_is_interruptible, write_fault, read_fault, fetch_fault;

    logic [$clog2(MEM_READ_PORTS)-1:0] write_fault_idx, read_fault_idx, fetch_fault_idx;

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
        end

        // Check the memory faults
        read_fault = '0;
        write_fault = '0;
        fetch_fault = '0;
        read_fault_idx = '0;
        write_fault_idx = '0;
        fetch_fault_idx = '0;
        for (int i = 0; i < MEM_READ_PORTS; i++) begin
            // Fetch > write > read
            case (mem_fault_i[i])
                FAULT_NONE : ;
                PMA_FETCH, PMP_FETCH : begin
                    fetch_fault = '1;
                    fetch_fault_idx = $clog2(MEM_READ_PORTS)'(unsigned'(i));
                end
                PMA_WRITE, PMP_WRITE : begin
                    write_fault = '1;
                    write_fault_idx = $clog2(MEM_READ_PORTS)'(unsigned'(i));
                end
                PMA_READ, PMP_READ : begin
                    read_fault = '1;
                    read_fault_idx = $clog2(MEM_READ_PORTS)'(unsigned'(i));
                end
                default : ;
            endcase
        end

        // This ordering implicitly resolves the mcause ordering
        // I have decided that hardware error is top priority of all synchronous traps.
        if (hardware_fault_i) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = HARDWARE_ERROR;

            if (medeleg_mod[HARDWARE_ERROR] && current_privilege_i < M_MODE) begin
                trap_o.dest_machine_privilege = S_MODE;
            end
        end else if (fetch_page_fault_i) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = INSTRUCTION_PAGE_FAULT;
            trap_o.tval = page_fault_addr_i;

            if (medeleg_mod[INSTRUCTION_PAGE_FAULT] && current_privilege_i < M_MODE) begin
                trap_o.dest_machine_privilege = S_MODE;
            end
        end else if (fetch_fault) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = INST_ACCESS_FAULT;
            trap_o.tval = mem_fault_addr_i[fetch_fault_idx];

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
        end else if (store_page_fault_i) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = STORE_PAGE_FAULT;
            trap_o.tval = page_fault_addr_i;

            if (medeleg_mod[STORE_PAGE_FAULT] && current_privilege_i < M_MODE) begin
                trap_o.dest_machine_privilege = S_MODE;
            end
        end else if (load_page_fault_i) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = LOAD_PAGE_FAULT;
            trap_o.tval = page_fault_addr_i;

            if (medeleg_mod[LOAD_PAGE_FAULT] && current_privilege_i < M_MODE) begin
                trap_o.dest_machine_privilege = S_MODE;
            end
        end else if (write_fault) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = STORE_ACCESS_FAULT;
            trap_o.tval = mem_fault_addr_i[write_fault_idx];

            if (medeleg_mod[STORE_ACCESS_FAULT] && current_privilege_i < M_MODE) begin
                trap_o.dest_machine_privilege = S_MODE;
            end
        end else if (read_fault) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = LOAD_ACCESS_FAULT;
            trap_o.tval = mem_fault_addr_i[read_fault_idx];

            if (medeleg_mod[LOAD_ACCESS_FAULT] && current_privilege_i < M_MODE) begin
                trap_o.dest_machine_privilege = S_MODE;
            end
        end
    end
endmodule : trap_controller
