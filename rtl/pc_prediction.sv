import riscv::*;

module pc_prediction (
    input logic [XLEN-1:0]  if_fetch_pc_i,
    output logic [XLEN-1:0] if_pred_pc_o
);
    assign if_pred_pc_o = if_fetch_pc_i + 'd4;
endmodule : pc_prediction
