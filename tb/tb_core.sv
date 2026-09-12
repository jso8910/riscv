`timescale 1ns/1ps

import riscv::*;

// Core smoke test using the post-MMU instruction-memory interface.  Translation
// is Bare in reset M-mode, so the instruction address is also the program PC.
module tb_core;
    logic clk, rst_n;
    logic [WWIDTH-1:0] inst_mem_data, data_mem_data;
    logic [XLEN-1:0] time_i, inst_mem_addr, data_mem_addr, data_mem_write_data;
    logic [WWIDTH/8-1:0] data_mem_we;
    logic mtime_we;
    int tests_run, tests_failed;

    riscv_core dut (
        .clk(clk), .rst_n(rst_n), .inst_mem_data_i(inst_mem_data),
        .data_mem_data_i(data_mem_data), .time_i(time_i),
        .inst_mem_addr_o(inst_mem_addr), .data_mem_we_o(data_mem_we),
        .data_mem_addr_o(data_mem_addr), .data_mem_data_o(data_mem_write_data),
        .mtime_we_o(mtime_we)
    );

    always #5 clk = ~clk;

    always_comb begin
        inst_mem_data = '0;
        case (inst_mem_addr)
            RESET_PC:      inst_mem_data[31:0] = 32'h0010_0093; // addi x1, x0, 1
            RESET_PC + 4:  inst_mem_data[31:0] = 32'h0010_8463; // beq x1, x1, +8
            RESET_PC + 8:  inst_mem_data[31:0] = 32'h0630_0113; // wrong path: addi x2, x0, 99
            RESET_PC + 12: inst_mem_data[31:0] = 32'h0030_0193; // target: addi x3, x0, 3
            default:       inst_mem_data[31:0] = RISCV_NOP;
        endcase
    end

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
        clk = 0;
        rst_n = 0;
        data_mem_data = '0;
        time_i = '0;
        tests_run = 0;
        tests_failed = 0;

        repeat (2) @(posedge clk);
        #1;
        check("reset holds the instruction address at RESET_PC", inst_mem_addr == RESET_PC);
        check("reset clears general-purpose registers", dut.u_regfile.regs[1] == '0);

        rst_n = 1;
        repeat (8) @(posedge clk);
        #1;
        check("instruction-memory path executes the first ALU instruction", dut.u_regfile.regs[1] == 64'd1);
        check("taken branch discards its sequential wrong-path instruction", dut.u_regfile.regs[2] == '0);
        check("taken branch fetches and executes its target", dut.u_regfile.regs[3] == 64'd3);
        check("ALU-only program does not issue a data write", data_mem_we == '0);
        check("retirement advances across branch recovery", dut.u_csrfile.minstret >= 64'd3);

        if (tests_failed == 0) begin
            $display("tb_core: all %0d checks passed", tests_run);
            $finish;
        end else
            $fatal(1, "tb_core: %0d of %0d checks failed", tests_failed, tests_run);
    end
endmodule : tb_core
