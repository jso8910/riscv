import riscv::*;

module timer_interrupt (
    input logic             clk,
    input logic             rst_n,
    input logic [XLEN-1:0]  time_i,
    input logic [XLEN-1:0]  mtimecmp_i,
    input logic             mtimecmp_we_i,
    input logic [XLEN-1:0]  stimecmp_i,
    output logic            mtip_o,
    output logic            stip_o,
    output logic [XLEN-1:0] mtimecmp_o
);
    logic [XLEN-1:0] mtimecmp;
    assign mtip_o = time_i >= mtimecmp;
    assign stip_o = time_i >= stimecmp_i;

    assign mtimecmp_o = mtimecmp;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mtimecmp <= '0;
        end else begin
            if (mtimecmp_we_i) begin
                mtimecmp <= mtimecmp_i;
            end
        end
    end
endmodule : timer_interrupt
