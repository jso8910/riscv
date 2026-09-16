import riscv::*;

module alu (
    input ctrl_t            ctrl_i,
    input logic [XLEN-1:0]  op1_data_i,
    input logic [XLEN-1:0]  op2_data_i,
    input logic [XLEN-1:0]  imm_i,
    output logic [XLEN-1:0] res_o
);
    // Wire instantiation
    logic [XLEN-1:0] op1, op2, res;
    logic [31:0] op1_32, op2_32, res32;
    logic signed [31:0] op1_32signed, op2_32signed;
    logic signed [XLEN-1:0] op1_signed, op2_signed;
    logic alu_op_found;
    logic [5:0] shamt;

    // Wire assignments
    assign op1 = op1_data_i;
    assign op2 = ctrl_i.alu_sel_imm ? imm_i : op2_data_i;

    assign op1_32 = op1[31:0];
    assign op2_32 = op2[31:0];
    assign op1_32signed = signed'(op1_32), op2_32signed = signed'(op2_32);

    assign op1_signed = signed'(op1), op2_signed = signed'(op2);
    assign shamt = op2[5:0];

    always_comb begin
        // Default value to prevent inferring a latch
        res = XLEN'(1'b0);
        res32 = 32'b0;
        alu_op_found = '1;
        if (ctrl_i.alu_word_op) begin
            case (ctrl_i.alu_op)
                ALU_ADD : res32 = op1_32 + op2_32;
                ALU_SUB : res32 = op1_32 - op2_32;
                ALU_SLT : res32 = (op1_32signed < op2_32signed) ? 32'b1 : 32'b0;
                ALU_SLTU : res32 = (op1_32 < op2_32) ? 32'b1 : 32'b0;
                ALU_XOR : res32 = op1_32 ^ op2_32;
                ALU_OR : res32 = op1_32 | op2_32;
                ALU_AND : res32 = op1_32 & op2_32;
                ALU_SLL : res32 = op1_32 << shamt[4:0];
                ALU_SRL : res32 = op1_32 >> shamt[4:0];
                // TODO is this correct?
                ALU_SRA : res32 = unsigned'(op1_32signed >>> shamt[4:0]);
                default : begin
                    alu_op_found = '0;
                    assert (1'b0);
                end
            endcase
            res_o = {{32{res32[31]}}, res32};
        end else begin
            case (ctrl_i.alu_op)
                ALU_ADD : res = op1 + op2;
                ALU_SUB : res = op1 - op2;
                ALU_SLT : res = (op1_signed < op2_signed) ? XLEN'(1'b1) : XLEN'(1'b0);
                ALU_SLTU : res = (op1 < op2) ? XLEN'(1'b1) : XLEN'(1'b0);
                ALU_XOR : res = op1 ^ op2;
                ALU_OR : res = op1 | op2;
                ALU_AND : res = op1 & op2;
                ALU_SLL : res = op1 << shamt;
                ALU_SRL : res = op1 >> shamt;
                // TODO is this correct?
                ALU_SRA : res = unsigned'(op1_signed >>> shamt);
                default : begin
                    alu_op_found = '0;
                    assert (1'b0);
                end
            endcase
            res_o = res;
        end
    end

    // Formal verification
    `ifdef FORMAL
    always_comb begin
        assert (alu_op_found);

        // Word operations must sign-extend their low 32-bit result.
        if (ctrl_i.alu_word_op) begin
            assert (res_o == {{(XLEN-32){res_o[31]}}, res_o[31:0]});
        end
    end
    `endif
endmodule : alu
