`timescale 1ns/1ps

import riscv::*;

module tb_memory_controller_sram;
    localparam int TEST_DWIDTH = 32;
    localparam int TEST_AWIDTH = 32;
    localparam logic [TEST_AWIDTH-1:0] TEST_START = 32'h0000_2000;
    localparam logic [TEST_AWIDTH-1:0] TEST_END   = 32'h0000_201f;
    localparam logic [TEST_AWIDTH-1:0] BASE_ADDR  = TEST_START + 32'd8;

    logic                         clk;
    logic [TEST_AWIDTH-1:0]       address;
    logic [TEST_DWIDTH-1:0]       store_data;
    logic [TEST_DWIDTH-1:0]       raw_data;
    logic [TEST_DWIDTH-1:0]       load_data;
    logic [(TEST_DWIDTH/8)-1:0]   we;
    ctrl_t                        ctrl;
    logic                         commit;

    int tests_run;
    int tests_failed;

    sram #(
        .DWIDTH(TEST_DWIDTH),
        .AWIDTH(TEST_AWIDTH),
        .START_ADDRESS(TEST_START),
        .END_ADDRESS(TEST_END)
    ) memory (
        .clk(clk),
        .address_i(address),
        .data_i(store_data),
        .we_i(we),
        .data_o(raw_data)
    );

    memory_controller controller (
        .data_i(raw_data),
        .ctrl_i(ctrl),
        .commit_i(commit),
        .data_o(load_data),
        .we_o(we)
    );

    always #5 clk = ~clk;

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

    task automatic store_through_controller(
        input logic [TEST_AWIDTH-1:0] addr,
        input logic [TEST_DWIDTH-1:0] data,
        input mem_size_t              mem_size
    );
        begin
            address = addr;
            store_data = data;
            set_ctrl(1'b0, 1'b1, mem_size, MEM_SIGNED);
            #1;
            @(posedge clk);
            #1;
            set_ctrl(1'b0, 1'b0, MEM_NONE, MEM_SIGNED);
            store_data = '0;
        end
    endtask

    task automatic disabled_store_attempt(
        input logic [TEST_AWIDTH-1:0] addr,
        input logic [TEST_DWIDTH-1:0] data,
        input mem_size_t              mem_size
    );
        begin
            address = addr;
            store_data = data;
            set_ctrl(1'b0, 1'b0, mem_size, MEM_SIGNED);
            #1;
            @(posedge clk);
            #1;
            store_data = '0;
        end
    endtask

    task automatic check_load(
        input string                   name,
        input logic [TEST_AWIDTH-1:0]  addr,
        input mem_size_t               mem_size,
        input mem_signed_t             mem_signed,
        input logic [TEST_DWIDTH-1:0]  expected
    );
        begin
            address = addr;
            set_ctrl(1'b1, 1'b0, mem_size, mem_signed);
            #1;

            tests_run++;
            if (load_data !== expected) begin
                tests_failed++;
                $fatal(1, "%s: expected load 0x%08x, got 0x%08x",
                       name, expected, load_data);
            end
        end
    endtask

    task automatic check_raw_word(
        input string                   name,
        input logic [TEST_AWIDTH-1:0]  addr,
        input logic [TEST_DWIDTH-1:0]  expected
    );
        begin
            address = addr;
            set_ctrl(1'b0, 1'b0, MEM_NONE, MEM_SIGNED);
            #1;

            tests_run++;
            if (raw_data !== expected) begin
                tests_failed++;
                $fatal(1, "%s: expected raw word 0x%08x, got 0x%08x",
                       name, expected, raw_data);
            end
        end
    endtask

    task automatic check_idle_outputs(
        input string                  name,
        input logic [TEST_AWIDTH-1:0] addr
    );
        begin
            address = addr;
            set_ctrl(1'b0, 1'b0, MEM_WORD, MEM_SIGNED);
            #1;

            tests_run++;
            if (load_data !== '0) begin
                tests_failed++;
                $fatal(1, "%s data: expected 0x%08x, got 0x%08x",
                       name, '0, load_data);
            end
            if (we !== '0) begin
                tests_failed++;
                $fatal(1, "%s we: expected 0b%04b, got 0b%04b",
                       name, '0, we);
            end
        end
    endtask

    task automatic clear_memory;
        begin
            for (int offset = 0; offset < 32; offset += TEST_DWIDTH / 8) begin
                store_through_controller(TEST_START + offset[TEST_AWIDTH-1:0],
                                         '0, MEM_WORD);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        address = TEST_START;
        store_data = '0;
        ctrl = '0;
        commit = 1'b1;
        tests_run = 0;
        tests_failed = 0;

        clear_memory();

        check_idle_outputs("idle controller leaves sram untouched", BASE_ADDR);

        store_through_controller(BASE_ADDR, 32'h1122_3344, MEM_WORD);
        check_raw_word("word store reaches sram unchanged",
                       BASE_ADDR, 32'h1122_3344);
        check_load("word load returns full sram word",
                   BASE_ADDR, MEM_WORD, MEM_SIGNED, 32'h1122_3344);

        store_through_controller(BASE_ADDR + 32'd1, 32'h0000_00aa, MEM_BYTE);
        check_raw_word("byte store updates only addressed byte",
                       BASE_ADDR, 32'h1122_aa44);
        check_load("signed byte load sign extends sram byte",
                   BASE_ADDR + 32'd1, MEM_BYTE, MEM_SIGNED, 32'hffff_ffaa);
        check_load("unsigned byte load zero extends sram byte",
                   BASE_ADDR + 32'd1, MEM_BYTE, MEM_UNSIGNED, 32'h0000_00aa);

        store_through_controller(BASE_ADDR + 32'd2, 32'h0000_8877, MEM_HALF);
        check_raw_word("halfword store updates addressed byte pair",
                       BASE_ADDR, 32'h8877_aa44);
        check_load("signed halfword load sign extends sram bytes",
                   BASE_ADDR + 32'd2, MEM_HALF, MEM_SIGNED, 32'hffff_8877);
        check_load("unsigned halfword load zero extends sram bytes",
                   BASE_ADDR + 32'd2, MEM_HALF, MEM_UNSIGNED, 32'h0000_8877);

        store_through_controller(BASE_ADDR + 32'd1, 32'h0000_55cc, MEM_HALF);
        check_raw_word("unaligned halfword store is address-relative",
                       BASE_ADDR, 32'h8855_cc44);
        check_load("unaligned halfword load is address-relative",
                   BASE_ADDR + 32'd1, MEM_HALF, MEM_UNSIGNED, 32'h0000_55cc);

        disabled_store_attempt(BASE_ADDR, 32'hffff_ffff, MEM_WORD);
        check_raw_word("disabled write does not change sram contents",
                       BASE_ADDR, 32'h8855_cc44);

        if (tests_failed == 0) begin
            $display("tb_memory_controller_sram: all %0d checks passed",
                     tests_run);
            $finish;
        end else begin
            $fatal(1, "tb_memory_controller_sram: %0d of %0d checks failed",
                   tests_failed, tests_run);
        end
    end
endmodule : tb_memory_controller_sram
