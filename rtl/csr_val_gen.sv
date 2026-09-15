import riscv::*;

module csr_val_gen (
    input ctrl_t            ctrl_i,
    input logic [XLEN-1:0]  rs1_data_i,
    input logic [XLEN-1:0]  csr_val_i,
    output logic [XLEN-1:0] csr_data_o
);
    logic [XLEN-1:0] rs1_uimm_chosen;
    // We want to either 0 extend a 5 bit immediate (stored in the rs1 address field) or take the
    // value of rs1
    assign rs1_uimm_chosen = ctrl_i.csr_imm ? {(XLEN-5)'(1'b0), ctrl_i.rs1_addr} : rs1_data_i;

    always_comb begin
        case (ctrl_i.csr_wb_sel)
            WB_NORMAL : csr_data_o = rs1_uimm_chosen;
            WB_SET_BITS : csr_data_o = csr_val_i | rs1_uimm_chosen;
            WB_CLEAR_BITS : csr_data_o = csr_val_i & (~rs1_uimm_chosen);
            default : csr_data_o = '0;
        endcase   
    end
endmodule : csr_val_gen
