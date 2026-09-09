`timescale 1ns/1ps

import riscv::*;

module tb_alu;
    ctrl_t            ctrl;
    logic [XLEN-1:0]  op1_data;
    logic [XLEN-1:0]  op2_data;
    logic [XLEN-1:0]  imm;
    logic [XLEN-1:0]  res;

    int tests_run;
    int tests_failed;

    alu dut (
        .ctrl_i(ctrl),
        .op1_data_i(op1_data),
        .op2_data_i(op2_data),
        .imm_i(imm),
        .res_o(res)
    );

    task automatic check(
        input string            name,
        input logic             sel_imm,
        input logic             word_op,
        input logic [XLEN-1:0]  rs1,
        input logic [XLEN-1:0]  rs2,
        input alu_op_t          alu_op,
        input logic [XLEN-1:0]  immediate,
        input logic [XLEN-1:0]  expected
    );
        begin
            ctrl = '0;
            ctrl.alu_sel_imm = sel_imm;
            ctrl.alu_word_op = word_op;
            ctrl.alu_op = alu_op;
            op1_data = rs1;
            op2_data = rs2;
            imm = immediate;
            #1;

            tests_run++;
            if (res !== expected) begin
                tests_failed++;
                $fatal(1, "%s: expected 0x%016x, got 0x%016x", name, expected, res);
            end
        end
    endtask

    initial begin
        tests_run = 0;
        tests_failed = 0;

        check("ADD positive values",
              1'b0, 1'b0, 64'd12, 64'd30, ALU_ADD, '0, 64'd42);
        check("ADD wraps on overflow",
              1'b0, 1'b0, 64'hffff_ffff_ffff_ffff, 64'd1, ALU_ADD, '0, '0);
        check("ADDI uses immediate operand",
              1'b1, 1'b0, 64'd7, 64'd99, ALU_ADD, 64'd5, 64'd12);
        check("SUB positive result",
              1'b0, 1'b0, 64'd30, 64'd12, ALU_SUB, '0, 64'd18);
        check("SUB wraps on underflow",
              1'b0, 1'b0, '0, 64'd1, ALU_SUB, '0, 64'hffff_ffff_ffff_ffff);

        check("SLT negative less than positive",
              1'b0, 1'b0, 64'hffff_ffff_ffff_ffff, 64'd1, ALU_SLT, '0, 64'd1);
        check("SLT positive not less than negative",
              1'b0, 1'b0, 64'd1, 64'hffff_ffff_ffff_ffff, ALU_SLT, '0, '0);
        check("SLTU max unsigned not less than zero",
              1'b0, 1'b0, 64'hffff_ffff_ffff_ffff, '0, ALU_SLTU, '0, '0);
        check("SLTU zero less than max unsigned",
              1'b0, 1'b0, '0, 64'hffff_ffff_ffff_ffff, ALU_SLTU, '0, 64'd1);

        check("XOR",
              1'b0, 1'b0, 64'haaaa_5555_aaaa_5555, 64'hffff_0000_ffff_0000, ALU_XOR, '0, 64'h5555_5555_5555_5555);
        check("OR",
              1'b0, 1'b0, 64'h1234_0000_1234_0000, 64'h0000_abcd_0000_abcd, ALU_OR, '0, 64'h1234_abcd_1234_abcd);
        check("AND",
              1'b0, 1'b0, 64'hffff_00ff_ffff_00ff, 64'h0f0f_0f0f_0f0f_0f0f, ALU_AND, '0, 64'h0f0f_000f_0f0f_000f);

        check("SLL register shift",
              1'b0, 1'b0, 64'd1, 64'd8, ALU_SLL, '0, 64'h0000_0000_0000_0100);
        check("SLL uses the RV64 shift amount",
              1'b0, 1'b0, 64'd1, 64'd32, ALU_SLL, '0, 64'h0000_0001_0000_0000);
        check("SLL masks shift amount at six bits",
              1'b0, 1'b0, 64'd1, 64'd64, ALU_SLL, '0, 64'd1);
        check("SRL",
              1'b0, 1'b0, 64'h8000_0000_0000_0000, 64'd4, ALU_SRL, '0, 64'h0800_0000_0000_0000);
        check("SRA",
              1'b0, 1'b0, 64'h8000_0000_0000_0000, 64'd4, ALU_SRA, '0, 64'hf800_0000_0000_0000);
        check("SRAI uses immediate shift amount",
              1'b1, 1'b0, 64'h8000_0000_0000_0000, '0, ALU_SRA, 64'd4, 64'hf800_0000_0000_0000);

        check("ADDW sign extends its 32-bit result",
              1'b0, 1'b1, 64'h0000_0000_7fff_ffff, 64'd1, ALU_ADD, '0, 64'hffff_ffff_8000_0000);
        check("SRAW sign extends its 32-bit result",
              1'b0, 1'b1, 64'h0000_0000_8000_0000, 64'd4, ALU_SRA, '0, 64'hffff_ffff_f800_0000);
        check("SLLW accepts bit 4 of its five-bit shift amount",
              1'b0, 1'b1, 64'd1, 64'd31, ALU_SLL, '0, 64'hffff_ffff_8000_0000);
        check("SLLW masks its shift amount at five bits",
              1'b0, 1'b1, 64'd1, 64'd32, ALU_SLL, '0, 64'd1);

        if (tests_failed == 0) begin
            $display("tb_alu: all %0d tests passed", tests_run);
            $finish;
        end else begin
            $fatal(1, "tb_alu: %0d of %0d tests failed", tests_failed, tests_run);
        end
    end
endmodule : tb_alu
