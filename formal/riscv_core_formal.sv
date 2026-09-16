import riscv::*;

// Formal-only top level. It establishes architectural reset before allowing
// the unconstrained environment to exercise the core.
module riscv_core_formal (
    input logic              clk,
    input logic [WWIDTH-1:0] inst_mem_data_i,
    input logic [WWIDTH-1:0] data_mem_data_i,
    input logic [XLEN-1:0]   time_i
);
    // 00 initially: reset asserted.
    // 01 after the first rising edge: the DUT has sampled reset.
    // 11 after the second rising edge: formal checks may be considered active.
    logic [1:0] reset_phase = 2'b00;
    always_ff @(posedge clk) begin
        if (!reset_phase[1])
            reset_phase <= {reset_phase[0], 1'b1};
    end

    logic rst_n;
    assign rst_n = reset_phase[0];

    riscv_core dut (
        .clk,
        .rst_n,
        .inst_mem_data_i,
        .data_mem_data_i,
        .time_i,
        .inst_mem_addr_o(),
        .data_mem_we_o(),
        .data_mem_addr_o(),
        .data_mem_data_o(),
        .mtime_we_o()
    );
endmodule : riscv_core_formal
