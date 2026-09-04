import riscv::*;

module trap_controller(
    input ctrl_t              ctrl_i,
    input logic               csr_illegal_inst_i,
    input logic               address_misaligned_i,
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

        // This ordering implicitly resolves the mcause ordering
        if (address_misaligned_i) begin
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
        end
    end
endmodule : trap_controller
