`timescale 1ns/1ps

import riscv::*;

module tb_timer_interrupt;
    logic clk;
    logic rst_n;
    logic [XLEN-1:0] time_i;
    logic [XLEN-1:0] mtimecmp_i;
    logic mtimecmp_we_i;
    logic [XLEN-1:0] stimecmp_i;
    logic mtip_o;
    logic stip_o;
    logic [XLEN-1:0] mtimecmp_o;
    int tests_run;
    int tests_failed;

    timer_interrupt dut (
        .clk(clk),
        .rst_n(rst_n),
        .time_i(time_i),
        .mtimecmp_i(mtimecmp_i),
        .mtimecmp_we_i(mtimecmp_we_i),
        .stimecmp_i(stimecmp_i),
        .mtip_o(mtip_o),
        .stip_o(stip_o),
        .mtimecmp_o(mtimecmp_o)
    );

    always #5 clk = ~clk;

    task automatic check(input string name, input logic condition);
        begin
            tests_run++;
            if (!condition) begin
                tests_failed++;
                $fatal(1, "%s", name);
            end
        end
    endtask

    task automatic write_mtimecmp(input logic [XLEN-1:0] value);
        begin
            mtimecmp_i = value;
            mtimecmp_we_i = 1'b1;
            @(posedge clk);
            #1;
            mtimecmp_we_i = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b1;
        time_i = '0;
        mtimecmp_i = '0;
        mtimecmp_we_i = 1'b0;
        stimecmp_i = '1;
        tests_run = 0;
        tests_failed = 0;

        rst_n = 1'b0;
        #1;
        check("mtimecmp resets to zero", mtimecmp_o == '0);
        check("reset compare is pending at time zero", mtip_o == 1'b1);

        rst_n = 1'b1;
        write_mtimecmp(64'd10);
        check("MTIMECMP readback observes programmed value", mtimecmp_o == 64'd10);
        check("MTIP clears when compare is in the future", mtip_o == 1'b0);

        time_i = 64'd9;
        #1;
        check("MTIP remains clear before compare", mtip_o == 1'b0);
        time_i = 64'd10;
        #1;
        check("MTIP asserts at compare", mtip_o == 1'b1);

        write_mtimecmp(64'd20);
        check("reprogramming compare deasserts MTIP", mtip_o == 1'b0);
        stimecmp_i = 64'd10;
        #1;
        check("STIP asserts at its compare", stip_o == 1'b1);

        if (tests_failed == 0) begin
            $display("tb_timer_interrupt: all %0d checks passed", tests_run);
            $finish;
        end else begin
            $fatal(1, "tb_timer_interrupt: %0d of %0d checks failed", tests_failed, tests_run);
        end
    end
endmodule : tb_timer_interrupt
