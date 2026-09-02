`timescale 1ns/1ps

import riscv::*;

module tb_fetch;
    logic             clk;
    logic             rst_n;
    logic [XLEN-1:0]  next_pc;
    logic [XLEN-1:0]  pc;

    int tests_run;
    int tests_failed;

    fetch dut (
        .clk(clk),
        .rst_n(rst_n),
        .next_pc_i(next_pc),
        .pc_o(pc)
    );

    always #5 clk = ~clk;

    task automatic check_fetch(
        input string             name,
        input logic [XLEN-1:0]   expected_pc
    );
        begin
            #1;
            tests_run++;
            if (pc !== expected_pc) begin
                tests_failed++;
                $error("%s pc: expected 0x%08x, got 0x%08x",
                       name, expected_pc, pc);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b1;
        next_pc = RESET_PC;
        tests_run = 0;
        tests_failed = 0;

        rst_n = 1'b0;
        #1;
        check_fetch("reset sets pc to reset vector",
                    RESET_PC);

        next_pc = 32'h0000_0004;
        rst_n = 1'b1;
        @(posedge clk);
        check_fetch("pc updates to next_pc",
                    32'h0000_0004);

        next_pc = 32'h0000_0008;
        @(posedge clk);
        check_fetch("pc follows next sequential value",
                    32'h0000_0008);

        next_pc = 32'h0000_0002;
        @(posedge clk);
        check_fetch("pc accepts next_pc input directly",
                    32'h0000_0002);

        next_pc = 32'h0000_0020;
        @(posedge clk);
        check_fetch("pc can jump to arbitrary next_pc",
                    32'h0000_0020);

        if (tests_failed == 0) begin
            $display("tb_fetch: all %0d checks passed", tests_run);
            $finish;
        end

        $fatal(1, "tb_fetch: %0d of %0d checks failed", tests_failed, tests_run);
    end
endmodule : tb_fetch
