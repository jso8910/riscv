`timescale 1ns/1ps

import riscv::*;

module tb_core;
    logic clk;
    logic rst_n;
    logic [IALIGN-1:0] inst;
    logic [WWIDTH-1:0] data_mem_data;
    logic [XLEN-1:0] pc;
    logic [WWIDTH/8-1:0] data_mem_we;
    logic [XLEN-1:0] data_mem_addr;
    logic [WWIDTH-1:0] data_mem_write_data;

    int tests_run;
    int tests_failed;

    riscv_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .inst_i(inst),
        .data_mem_data_i(data_mem_data),
        .pc_o(pc),
        .data_mem_we_o(data_mem_we),
        .data_mem_addr_o(data_mem_addr),
        .data_mem_data_o(data_mem_write_data)
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
                $fatal(1, "%s", name);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        inst = 32'h0000_0013; // addi x0, x0, 0
        data_mem_data = '0;
        tests_run = 0;
        tests_failed = 0;

        #1;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        check("riscv_core smoke test reached after reset", pc[1:0] == 2'b00);

        if (tests_failed == 0) begin
            $display("tb_core: all %0d checks passed", tests_run);
            $finish;
        end else begin
            $fatal(1, "tb_core: %0d of %0d checks failed", tests_failed, tests_run);
        end
    end
endmodule : tb_core
