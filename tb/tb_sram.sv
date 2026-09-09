`timescale 1ns/1ps

import riscv::*;

module tb_sram;
    localparam int TEST_DWIDTH = 32;
    localparam int TEST_AWIDTH = 32;
    localparam logic [TEST_AWIDTH-1:0] TEST_START = 32'h0000_1000;
    localparam logic [TEST_AWIDTH-1:0] TEST_END   = 32'h0000_101f;

    logic                         clk;
    logic [TEST_AWIDTH-1:0]       address_1;
    logic [TEST_AWIDTH-1:0]       address_2;
    logic [TEST_DWIDTH-1:0]       data_in;
    logic [(TEST_DWIDTH/8)-1:0]   we;
    logic [TEST_DWIDTH-1:0]       data_1_out;
    logic [TEST_DWIDTH-1:0]       data_2_out;

    int tests_run;
    int tests_failed;

    sram #(
        .DWIDTH(TEST_DWIDTH),
        .AWIDTH(TEST_AWIDTH),
        .START_ADDRESS(TEST_START),
        .END_ADDRESS(TEST_END)
    ) dut (
        .clk(clk),
        .address_1_i(address_1),
        .address_2_i(address_2),
        .data_i(data_in),
        .we_i(we),
        .data_1_o(data_1_out),
        .data_2_o(data_2_out)
    );

    always #5 clk = ~clk;

    task automatic write_mem(
        input logic [TEST_AWIDTH-1:0] addr,
        input logic [TEST_DWIDTH-1:0] data,
        input logic [(TEST_DWIDTH/8)-1:0] byte_en
    );
        begin
            address_1 = addr;
            data_in = data;
            we = byte_en;
            @(posedge clk);
            #1;
            we = '0;
        end
    endtask

    task automatic check_read(
        input string                  name,
        input logic [TEST_AWIDTH-1:0] addr,
        input logic [TEST_DWIDTH-1:0] expected
    );
        begin
            address_1 = addr;
            we = '0;
            #1;

            tests_run++;
            if (data_1_out !== expected) begin
                tests_failed++;
                $fatal(1, "%s: expected 0x%08x, got 0x%08x",
                       name, expected, data_1_out);
            end
        end
    endtask

    task automatic check_second_read(
        input string                  name,
        input logic [TEST_AWIDTH-1:0] addr,
        input logic [TEST_DWIDTH-1:0] expected
    );
        begin
            address_2 = addr;
            #1;

            tests_run++;
            if (data_2_out !== expected) begin
                tests_failed++;
                $fatal(1, "%s: expected 0x%08x, got 0x%08x",
                       name, expected, data_2_out);
            end
        end
    endtask

    task automatic check_simultaneous_reads(
        input string                  name,
        input logic [TEST_AWIDTH-1:0] first_addr,
        input logic [TEST_DWIDTH-1:0] first_expected,
        input logic [TEST_AWIDTH-1:0] second_addr,
        input logic [TEST_DWIDTH-1:0] second_expected
    );
        begin
            address_1 = first_addr;
            address_2 = second_addr;
            we = '0;
            #1;

            tests_run++;
            if (data_1_out !== first_expected || data_2_out !== second_expected) begin
                tests_failed++;
                $fatal(1, "%s: expected 0x%08x/0x%08x, got 0x%08x/0x%08x",
                       name, first_expected, second_expected, data_1_out, data_2_out);
            end
        end
    endtask

    task automatic check_byte(
        input string                  name,
        input logic [TEST_AWIDTH-1:0] addr,
        input logic [7:0]             expected
    );
        begin
            tests_run++;
            if (dut.mem[addr] !== expected) begin
                tests_failed++;
                $fatal(1, "%s: expected byte 0x%02x at 0x%08x, got 0x%02x",
                       name, expected, addr, dut.mem[addr]);
            end
        end
    endtask

    task automatic clear_test_memory;
        begin
            for (logic [TEST_AWIDTH-1:0] addr = TEST_START;
                 addr <= TEST_END;
                 addr += TEST_DWIDTH / 8) begin
                write_mem(addr, '0, '1);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        address_1 = TEST_START;
        address_2 = TEST_START;
        data_in = '0;
        we = '0;
        tests_run = 0;
        tests_failed = 0;

        clear_test_memory();

        check_read("cleared first word",
                   TEST_START, 32'h0000_0000);
        check_read("cleared last word",
                   TEST_END - 3, 32'h0000_0000);

        write_mem(TEST_START, 32'h1234_5678, 4'b1111);
        check_byte("little endian byte 0 is least significant byte",
                   TEST_START + 0, 8'h78);
        check_byte("little endian byte 1",
                   TEST_START + 1, 8'h56);
        check_byte("little endian byte 2",
                   TEST_START + 2, 8'h34);
        check_byte("little endian byte 3 is most significant byte",
                   TEST_START + 3, 8'h12);
        check_read("full word write/read",
                   TEST_START, 32'h1234_5678);
        check_second_read("second port reads the same shared memory",
                          TEST_START, 32'h1234_5678);

        write_mem(TEST_START, 32'haaaa_aaaa, 4'b0000);
        check_read("write enable zero leaves word unchanged",
                   TEST_START, 32'h1234_5678);

        write_mem(TEST_START, 32'hdead_beef, 4'b0101);
        check_byte("little endian byte enable lane 0 updates address plus 0",
                   TEST_START + 0, 8'hef);
        check_byte("little endian byte enable lane 1 remains address plus 1",
                   TEST_START + 1, 8'h56);
        check_byte("little endian byte enable lane 2 updates address plus 2",
                   TEST_START + 2, 8'had);
        check_byte("little endian byte enable lane 3 remains address plus 3",
                   TEST_START + 3, 8'h12);
        check_read("byte write enables update selected lanes",
                   TEST_START, 32'h12ad_56ef);

        write_mem(TEST_START + 4, 32'hcafebabe, 4'b1111);
        check_read("second full word write/read",
                   TEST_START + 4, 32'hcafe_babe);
        check_second_read("second port reads independently of first port",
                          TEST_START + 4, 32'hcafe_babe);
        check_simultaneous_reads("both ports can read distinct words simultaneously",
                                 TEST_START, 32'h12ad_56ef,
                                 TEST_START + 4, 32'hcafe_babe);
        check_read("unaligned read spans adjacent bytes",
                   TEST_START + 2, 32'hbabe_12ad);

        write_mem(TEST_START + 1, 32'h3344_5566, 4'b0110);
        check_read("unaligned byte enables map to address plus lane",
                   TEST_START, 32'h4455_56ef);

        write_mem(TEST_END - 1, 32'hddcc_bbaa, 4'b1111);
        check_read("upper boundary partial write keeps in-range bytes",
                   TEST_END - 3, 32'hbbaa_0000);
        check_read("upper out-of-range read bytes return zero",
                   TEST_END - 1, 32'h0000_bbaa);

        write_mem(TEST_START - 2, 32'h8877_6655, 4'b1111);
        check_read("lower boundary partial write keeps in-range bytes",
                   TEST_START, 32'h4455_8877);
        check_read("lower out-of-range read bytes return zero",
                   TEST_START - 2, 32'h8877_0000);

        if (tests_failed == 0) begin
            $display("tb_sram: all %0d tests passed", tests_run);
            $finish;
        end else begin
            $fatal(1, "tb_sram: %0d of %0d tests failed", tests_failed, tests_run);
        end
    end
endmodule : tb_sram
