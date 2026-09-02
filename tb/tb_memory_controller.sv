`timescale 1ns/1ps

import riscv::*;

module tb_memory_controller;
    logic [XLEN-1:0] data_in;
    ctrl_t           ctrl;
    logic [XLEN-1:0] data_out;
    logic [3:0]      we;

    int tests_run;
    int tests_failed;

    memory_controller dut (
        .data_i(data_in),
        .ctrl_i(ctrl),
        .data_o(data_out),
        .we_o(we)
    );

    task automatic set_ctrl(
        input logic        mem_read,
        input logic        mem_write,
        input mem_size_t   mem_size,
        input mem_signed_t mem_signed
    );
        begin
            ctrl = '0;
            ctrl.mem_read = mem_read;
            ctrl.mem_write = mem_write;
            ctrl.mem_size = mem_size;
            ctrl.mem_signed = mem_signed;
        end
    endtask

    task automatic check(
        input string            name,
        input logic [XLEN-1:0]  raw_data,
        input logic             mem_read,
        input logic             mem_write,
        input mem_size_t        mem_size,
        input mem_signed_t      mem_signed,
        input logic [XLEN-1:0]  expected_data,
        input logic [3:0]       expected_we
    );
        begin
            data_in = raw_data;
            set_ctrl(mem_read, mem_write, mem_size, mem_signed);
            #1;

            tests_run++;
            if (data_out !== expected_data) begin
                tests_failed++;
                $error("%s data: expected 0x%08x, got 0x%08x",
                       name, expected_data, data_out);
            end
            if (we !== expected_we) begin
                tests_failed++;
                $error("%s we: expected 0b%04b, got 0b%04b",
                       name, expected_we, we);
            end
        end
    endtask

    initial begin
        data_in = '0;
        ctrl = '0;
        tests_run = 0;
        tests_failed = 0;

        check("idle produces no read data or write enables",
              32'h89ab_cdef, 1'b0, 1'b0, MEM_WORD, MEM_SIGNED,
              '0, 4'b0000);

        check("byte write enables lane 0 at current address",
              32'h0000_0000, 1'b0, 1'b1, MEM_BYTE, MEM_SIGNED,
              '0, 4'b0001);
        check("halfword write enables lanes 0 and 1 at current address",
              32'h0000_0000, 1'b0, 1'b1, MEM_HALF, MEM_SIGNED,
              '0, 4'b0011);
        check("word write enables all lanes",
              32'h0000_0000, 1'b0, 1'b1, MEM_WORD, MEM_SIGNED,
              '0, 4'b1111);
        check("MEM_NONE write enables no lanes",
              32'h0000_0000, 1'b0, 1'b1, MEM_NONE, MEM_SIGNED,
              '0, 4'b0000);

        check("signed byte read positive",
              32'h0000_007f, 1'b1, 1'b0, MEM_BYTE, MEM_SIGNED,
              32'h0000_007f, 4'b0000);
        check("signed byte read negative",
              32'h0000_0080, 1'b1, 1'b0, MEM_BYTE, MEM_SIGNED,
              32'hffff_ff80, 4'b0000);
        check("unsigned byte read zero extends",
              32'h0000_0080, 1'b1, 1'b0, MEM_BYTE, MEM_UNSIGNED,
              32'h0000_0080, 4'b0000);

        check("signed halfword read positive",
              32'h0000_7fff, 1'b1, 1'b0, MEM_HALF, MEM_SIGNED,
              32'h0000_7fff, 4'b0000);
        check("signed halfword read negative",
              32'h0000_8000, 1'b1, 1'b0, MEM_HALF, MEM_SIGNED,
              32'hffff_8000, 4'b0000);
        check("unsigned halfword read zero extends",
              32'h0000_8000, 1'b1, 1'b0, MEM_HALF, MEM_UNSIGNED,
              32'h0000_8000, 4'b0000);

        check("word read passes full word",
              32'h89ab_cdef, 1'b1, 1'b0, MEM_WORD, MEM_SIGNED,
              32'h89ab_cdef, 4'b0000);
        check("MEM_NONE read returns zero",
              32'h89ab_cdef, 1'b1, 1'b0, MEM_NONE, MEM_SIGNED,
              '0, 4'b0000);

        if (tests_failed == 0) begin
            $display("tb_memory_controller: all %0d checks passed", tests_run);
            $finish;
        end

        $fatal(1, "tb_memory_controller: %0d of %0d checks failed",
               tests_failed, tests_run);
    end
endmodule : tb_memory_controller
