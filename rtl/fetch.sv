import riscv::*;

module fetch (
    input logic clk,
    input logic rst_n,
    input logic [XLEN-1:0] next_pc_i,
    output logic [XLEN-1:0] pc_o
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            pc_o <= RESET_PC;
        else
            pc_o <= next_pc_i;
    end
endmodule
