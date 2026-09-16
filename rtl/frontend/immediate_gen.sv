import riscv::*;

module immediate_gen (
    input logic [IALIGN-1:0] inst_i,
    input inst_fmt_t inst_fmt_i,
    output logic [XLEN-1:0] imm_o
);
    logic sign;
    logic [XLEN-1:0] imm_i;
    logic [XLEN-1:0] imm_s;
    logic [XLEN-1:0] imm_b;
    logic [XLEN-1:0] imm_u;
    logic [XLEN-1:0] imm_j;

    assign sign = inst_i[IMM_SIGN];
    assign imm_i = {{(XLEN-12){sign}}, inst_i[31:20]};
    assign imm_s = {{(XLEN-12){sign}}, inst_i[31:25], inst_i[11:7]};
    assign imm_b = {{(XLEN-13){sign}}, inst_i[31], inst_i[7], inst_i[30:25], inst_i[11:8], 1'b0};
    assign imm_u = {{(XLEN-31){inst_i[31]}}, inst_i[30:12], 12'b0};
    assign imm_j = {{(XLEN-21){sign}}, inst_i[31], inst_i[19:12], inst_i[20], inst_i[30:21], 1'b0};

    always_comb begin
        case (inst_fmt_i)
            IMM_R : imm_o = '0;
            IMM_I : imm_o = imm_i;
            IMM_S : imm_o = imm_s;
            IMM_B : imm_o = imm_b;
            IMM_U : imm_o = imm_u;
            IMM_J : imm_o = imm_j;
            default : imm_o = '0;
        endcase 
    end
endmodule : immediate_gen
