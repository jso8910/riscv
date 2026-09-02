import riscv::*;

module alu (
    input ctrl_t            ctrl_i,
    input logic [XLEN-1:0]  op1_data_i,
    input logic [XLEN-1:0]  op2_data_i,
    input logic [XLEN-1:0]  imm_i,
    output logic [XLEN-1:0] res_o
);
    // Wire instantiation
    logic [XLEN-1:0] op1, op2;
    logic signed [XLEN-1:0] op1_signed, op2_signed;
    logic [4:0] shamt;

    // Wire assignments
    assign op1 = op1_data_i;
    assign op2 = ctrl_i.alu_sel_imm ? imm_i : op2_data_i;
    assign op1_signed = op1, op2_signed = op2;
    assign shamt = op2[4:0];

    always_comb begin
        // Default value to prevent inferring a latch
        res_o = XLEN'(1'b0);
        case (ctrl_i.alu_op)
            ALU_ADD : res_o = op1 + op2;
            ALU_SUB : res_o = op1 - op2;
            ALU_SLT : res_o = (op1_signed < op2_signed) ? XLEN'(1'b1) : XLEN'(1'b0);
            ALU_SLTU : res_o = (op1 < op2) ? XLEN'(1'b1) : XLEN'(1'b0);
            ALU_XOR : res_o = op1 ^ op2;
            ALU_OR : res_o = op1 | op2;
            ALU_AND : res_o = op1 & op2;
            ALU_SLL : res_o = op1 << shamt;
            ALU_SRL : res_o = op1 >> shamt;
            ALU_SRA : res_o = op1_signed >>> shamt;
        endcase
    end
endmodule : alu
