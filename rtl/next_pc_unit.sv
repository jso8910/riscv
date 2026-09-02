import riscv::*;

module next_pc_unit (
    input ctrl_t            ctrl_i,
    input logic [XLEN-1:0]  pc_i,
    input logic [XLEN-1:0]  rs1_data_i,
    input logic [XLEN-1:0]  rs2_data_i,
    input logic [XLEN-1:0]  alu_res_i,
    output logic [XLEN-1:0] next_pc_o
);
    logic [XLEN-1:0] op1, op2;
    logic signed [XLEN-1:0] op1_signed, op2_signed;
    logic [XLEN-1:0] pc_seq, pc_branch;
    logic branch_taken;

    assign op1 = rs1_data_i, op2 = rs2_data_i;
    assign op1_signed = op1, op2_signed = op2;
    assign pc_seq = pc_i + PC_INC;
    assign next_pc_o = branch_taken ? pc_branch : pc_seq;

    always_comb begin
        pc_branch = alu_res_i;
        branch_taken = 1'b0;

        // Bit 0 must be cleared for JALR
        if (ctrl_i.jalr) pc_branch = pc_branch & ~(XLEN'(1'b1));

        if (ctrl_i.jal || ctrl_i.jalr) branch_taken = 1'b1;
        else if (ctrl_i.branch) begin
            case (ctrl_i.branch_cond)
                COND_EQ : branch_taken = op1 == op2;
                COND_NE : branch_taken = op1 != op2;
                COND_LT : branch_taken = op1_signed < op2_signed;
                COND_GE : branch_taken = op1_signed >= op2_signed;
                COND_LTU : branch_taken = op1 < op2;
                COND_GEU : branch_taken = op1 >= op2;
            endcase
        end
    end
endmodule
