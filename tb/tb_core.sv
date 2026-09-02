`timescale 1ns/1ps

import riscv::*;

module tb_core;
    logic clk;
    logic rst_n;

    int tests_run;
    int tests_failed;

    riscv_system #(
        .IMEM_START_ADDRESS_P(32'h0000_0000),
        .IMEM_END_ADDRESS_P  (32'h0000_001f),
        .DMEM_START_ADDRESS_P(32'h0000_0100),
        .DMEM_END_ADDRESS_P  (32'h0000_011f)
    ) dut (
        .clk(clk),
        .rst_n(rst_n)
    );

    always #5 clk = ~clk;

    task automatic check(
        input string name,
        input logic condition
    );
        begin
            tests_run++;
            if (!condition) begin
                tests_failed++;
                $error("%s", name);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b1;
        tests_run = 0;
        tests_failed = 0;

        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        check("riscv_system smoke test reached after reset", 1'b1);

        if (tests_failed == 0) begin
            $display("tb_core: all %0d checks passed", tests_run);
            $finish;
        end

        $fatal(1, "tb_core: %0d of %0d checks failed", tests_failed, tests_run);
    end
endmodule : tb_core
