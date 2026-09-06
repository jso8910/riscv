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
        input logic [XLEN-1:0]  rs1,
        input logic [XLEN-1:0]  rs2,
        input alu_op_t          alu_op,
        input logic [XLEN-1:0]  immediate,
        input logic [XLEN-1:0]  expected
    );
        begin
            ctrl = '0;
            ctrl.alu_sel_imm = sel_imm;
            ctrl.alu_op = alu_op;
            op1_data = rs1;
            op2_data = rs2;
            imm = immediate;
            #1;

            tests_run++;
            if (res !== expected) begin
                tests_failed++;
                $fatal(1, "%s: expected 0x%08x, got 0x%08x", name, expected, res);
            end
        end
    endtask

    initial begin
        tests_run = 0;
        tests_failed = 0;

        check("ADD positive values",
              1'b0, 32'd12, 32'd30, ALU_ADD, 32'd0, 32'd42);
        check("ADD wraps on overflow",
              1'b0, 32'hffff_ffff, 32'd1, ALU_ADD, 32'd0, 32'h0000_0000);
        check("ADDI uses immediate operand",
              1'b1, 32'd7, 32'd99, ALU_ADD, 32'd5, 32'd12);
        check("SUB positive result",
              1'b0, 32'd30, 32'd12, ALU_SUB, 32'd0, 32'd18);
        check("SUB wraps on underflow",
              1'b0, 32'd0, 32'd1, ALU_SUB, 32'd0, 32'hffff_ffff);

        check("SLT negative less than positive",
              1'b0, 32'hffff_ffff, 32'd1, ALU_SLT, 32'd0, 32'd1);
        check("SLT positive not less than negative",
              1'b0, 32'd1, 32'hffff_ffff, ALU_SLT, 32'd0, 32'd0);
        check("SLTU max unsigned not less than zero",
              1'b0, 32'hffff_ffff, 32'd0, ALU_SLTU, 32'd0, 32'd0);
        check("SLTU zero less than max unsigned",
              1'b0, 32'd0, 32'hffff_ffff, ALU_SLTU, 32'd0, 32'd1);

        check("XOR",
              1'b0, 32'haaaa_5555, 32'hffff_0000, ALU_XOR, 32'd0, 32'h5555_5555);
        check("OR",
              1'b0, 32'h1234_0000, 32'h0000_abcd, ALU_OR, 32'd0, 32'h1234_abcd);
        check("AND",
              1'b0, 32'hffff_00ff, 32'h0f0f_0f0f, ALU_AND, 32'd0, 32'h0f0f_000f);

        check("SLL register shift",
              1'b0, 32'h0000_0001, 32'd8, ALU_SLL, 32'd0, 32'h0000_0100);
        check("SLL masks shift amount",
              1'b0, 32'h0000_0001, 32'd32, ALU_SLL, 32'd0, 32'h0000_0001);
        check("SRL",
              1'b0, 32'h8000_0000, 32'd4, ALU_SRL, 32'd0, 32'h0800_0000);
        check("SRA",
              1'b0, 32'h8000_0000, 32'd4, ALU_SRA, 32'd0, 32'hf800_0000);
        check("SRAI uses immediate shift amount",
              1'b1, 32'h8000_0000, 32'd0, ALU_SRA, 32'd4, 32'hf800_0000);

        if (tests_failed == 0) begin
            $display("tb_alu: all %0d tests passed", tests_run);
            $finish;
        end else begin
            $fatal(1, "tb_alu: %0d of %0d tests failed", tests_failed, tests_run);
        end
    end
endmodule : tb_alu
