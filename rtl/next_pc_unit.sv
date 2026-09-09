import riscv::*;

module next_pc_unit (
    input ctrl_t            ctrl_i,
    input logic [XLEN-1:0]  pc_i,
    input logic [XLEN-1:0]  rs1_data_i,
    input logic [XLEN-1:0]  rs2_data_i,
    input logic [XLEN-1:0]  alu_res_i,
    input logic [XLEN-1:0]  mepc_i,
    input logic [XLEN-1:0]  mtvec_i,
    input trap_t            trap_i,
    output logic [XLEN-1:0] next_pc_o,
    output logic            address_misaligned_o
);
    logic [XLEN-1:0] op1, op2;
    logic signed [XLEN-1:0] op1_signed, op2_signed;
    logic [XLEN-1:0] pc_seq, pc_branch;
    logic branch_taken;

    assign op1 = rs1_data_i, op2 = rs2_data_i;
    assign op1_signed = signed'(op1), op2_signed = signed'(op2);
    assign pc_seq = pc_i + PC_INC;

    always_comb begin
        // In the case of a return from a trap, we want to branch to the MEPC
        case (ctrl_i.branch_src)
            SRC_ALU : pc_branch = alu_res_i;
            SRC_MEPC : pc_branch = mepc_i;
            default : $fatal(1);
        endcase
        branch_taken = 1'b0;
        address_misaligned_o = '0;

        // Bit 0 must be cleared for JALR
        if (ctrl_i.jalr) pc_branch = pc_branch & ~(XLEN'(1'b1));

        if (ctrl_i.jal || ctrl_i.jalr || ctrl_i.mret) branch_taken = 1'b1;
        else if (ctrl_i.branch) begin
            case (ctrl_i.branch_cond)
                COND_EQ : branch_taken = op1 == op2;
                COND_NE : branch_taken = op1 != op2;
                COND_LT : branch_taken = op1_signed < op2_signed;
                COND_GE : branch_taken = op1_signed >= op2_signed;
                COND_LTU : branch_taken = op1 < op2;
                COND_GEU : branch_taken = op1 >= op2;
                default : branch_taken = '1;
            endcase
        end

        // Set next PC
        if (trap_i.is_trap) begin
            case (trap_mode_t'(mtvec_i[1:0]))
                TRAP_DIRECT : next_pc_o = {mtvec_i[XLEN-1:2], 2'b00};
                TRAP_VEC : begin
                    // If an asynchronous interrupt, set PC to BASE + 4*cause
                    if (trap_i.is_interrupt) begin
                        next_pc_o = {mtvec_i[XLEN-1:2], 2'b00} + 4*(XLEN'(trap_i.interrupt_cause));
                    end else
                        next_pc_o = {mtvec_i[XLEN-1:2], 2'b00};
                end
                // MTVEC writes are legalized to direct or vectored mode. Use
                // direct mode defensively while reset-state signals settle.
                default: next_pc_o = {mtvec_i[XLEN-1:2], 2'b00};
            endcase
        end else if (branch_taken)
            next_pc_o = pc_branch;
        else
            next_pc_o = pc_seq;

        // If branch is not aligned
        // NOTE: must change if IALIGN changes.
        if (branch_taken && (pc_branch[1:0] != 2'b00))
            address_misaligned_o = '1;
    end
endmodule
