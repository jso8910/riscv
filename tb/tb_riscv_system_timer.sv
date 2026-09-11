`timescale 1ns/1ps

import riscv::*;

module tb_riscv_system_timer;
    logic clk;
    logic rst_n;
    int tests_run;
    int tests_failed;

    riscv_system #(
        .SRAM_END_ADDRESS('hff)
    ) dut (
        .clk(clk),
        .rst_n(rst_n)
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

    initial begin
        clk = 1'b0;
        rst_n = 1'b1;
        tests_run = 0;
        tests_failed = 0;
        // This harness exercises the platform timer, not instruction fetch.
        // Keep the otherwise uninitialized SRAM from presenting an illegal
        // instruction before reset takes effect.
        force dut.inst_i = 32'h0000_0013;

        rst_n = 1'b0;
        #1;
        check("external timer resets to zero", dut.mtime == '0);

        rst_n = 1'b1;
        repeat (3) @(posedge clk);
        #1;
        check("external timer advances once per core clock", dut.mtime == 64'd3);

        force dut.mtime_we = 1'b1;
        force dut.data_mem_data_o = 64'h0123_4567_89ab_cdef;
        @(posedge clk);
        #1;
        check("MTIME write updates external timer", dut.mtime == 64'h0123_4567_89ab_cdef);
        release dut.mtime_we;
        release dut.data_mem_data_o;
        @(posedge clk);
        #1;
        check("external timer resumes incrementing after write", dut.mtime == 64'h0123_4567_89ab_cdf0);

        if (tests_failed == 0) begin
            $display("tb_riscv_system_timer: all %0d checks passed", tests_run);
            $finish;
        end else begin
            $fatal(1, "tb_riscv_system_timer: %0d of %0d checks failed", tests_failed, tests_run);
        end
    end
endmodule : tb_riscv_system_timer
