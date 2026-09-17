// Smoke proof for rtl/misc/formal_temporal.svh.  This is deliberately small:
// it proves that the macro elaborates through the same Slang/Yosys frontend
// used by the core and that its $past() condition has the intended timing.
`include "../rtl/misc/formal_temporal.svh"

module formal_temporal_test (
    input logic clk,
    input logic data_i
);
    logic [1:0] reset_phase = 2'b00;
    logic rst_n;
    logic data_q;

    always_ff @(posedge clk) begin
        if (!reset_phase[1])
            reset_phase <= {reset_phase[0], 1'b1};
    end
    assign rst_n = reset_phase[0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            data_q <= 1'b0;
        else
            data_q <= data_i;
    end

`ifdef FORMAL
    `FORMAL_DECLARE_PAST_VALID(f_past_valid, clk, rst_n)

    // data_q at this edge is the value sampled from data_i at the preceding
    // edge.  This is the direct immediate-assertion equivalent of
    // "rst_n |-> data_q == $past(data_i)" after reset has completed.
    `FORMAL_ASSERT_NEXT(clk, f_past_valid,
        rst_n,
        rst_n && data_q == $past(data_i))
`endif
endmodule : formal_temporal_test
