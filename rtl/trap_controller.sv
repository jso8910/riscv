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

    input machine_privilege_t current_privilege_i,
    input [XLEN-1:0]          pc_i,
    output trap_t             trap_o
);
    always_comb begin
        trap_o = '0;
        trap_o.is_trap = '0;
        trap_o.is_interrupt = '0;
        trap_o.interrupt_cause = S_SOFTWARE;    // arbitrary
        trap_o.exception_cause = INST_ADDR_MISALIGNED; // arbitrary
        trap_o.pc = pc_i;
        trap_o.tval = '0;

        // This ordering implicitly resolves the mcause ordering
        // I have decided that hardware error is top priority
        if (hardware_fault_i) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = HARDWARE_ERROR;
        end else if (pmp_instruction_fetch_exception_i) begin
            // Note that PMP takes priority over PMA
            trap_o.is_trap = '1;
            trap_o.exception_cause = INST_ACCESS_FAULT;
            trap_o.tval = pmp_faulting_addr_i;
        end else if (pma_instruction_fetch_exception_i) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = INST_ACCESS_FAULT;
            trap_o.tval = pma_faulting_addr_i;
        end else if (address_misaligned_i) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = INST_ADDR_MISALIGNED;
        end else if (ctrl_i.illegal || csr_illegal_inst_i) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = ILLEGAL_INSTRUCTION;
        end else if (ctrl_i.ecall && current_privilege_i == M_MODE) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = ECALL_FROM_M_MODE;
        end else if (ctrl_i.ebreak) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = BREAKPOINT;
        end else if (pmp_write_exception_i) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = STORE_ACCESS_FAULT;
            trap_o.tval = pmp_faulting_addr_i;
        end else if (pma_write_exception_i) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = STORE_ACCESS_FAULT;
            trap_o.tval = pma_faulting_addr_i;
        end else if (pmp_read_exception_i) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = LOAD_ACCESS_FAULT;
            trap_o.tval = pmp_faulting_addr_i;
        end else if (pma_read_exception_i) begin
            trap_o.is_trap = '1;
            trap_o.exception_cause = LOAD_ACCESS_FAULT;
            trap_o.tval = pma_faulting_addr_i;
        end
    end
endmodule : trap_controller
