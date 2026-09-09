`timescale 1ns/1ps

import riscv::*;

module tb_immediate_gen;
    logic [IALIGN-1:0] inst;
    inst_fmt_t          inst_fmt;
    logic [XLEN-1:0]   imm;

    int tests_run;
    int tests_failed;

    immediate_gen dut (
        .inst_i(inst),
        .inst_fmt_i(inst_fmt),
        .imm_o(imm)
    );

    function automatic logic [IALIGN-1:0] enc_i(input logic [11:0] imm_i);
        enc_i = '0;
        enc_i[31:20] = imm_i;
        enc_i[6:0] = OP_IMM;
    endfunction

    function automatic logic [IALIGN-1:0] enc_s(input logic [11:0] imm_s);
        enc_s = '0;
        enc_s[31:25] = imm_s[11:5];
        enc_s[11:7] = imm_s[4:0];
        enc_s[6:0] = STORE;
    endfunction

    function automatic logic [IALIGN-1:0] enc_b(input logic [12:0] imm_b);
        enc_b = '0;
        enc_b[31] = imm_b[12];
        enc_b[7] = imm_b[11];
        enc_b[30:25] = imm_b[10:5];
        enc_b[11:8] = imm_b[4:1];
        enc_b[6:0] = BRANCH;
    endfunction

    function automatic logic [IALIGN-1:0] enc_u(input logic [19:0] imm_u);
        enc_u = '0;
        enc_u[31:12] = imm_u;
        enc_u[6:0] = LUI;
    endfunction

    function automatic logic [IALIGN-1:0] enc_j(input logic [20:0] imm_j);
        enc_j = '0;
        enc_j[31] = imm_j[20];
        enc_j[19:12] = imm_j[19:12];
        enc_j[20] = imm_j[11];
        enc_j[30:21] = imm_j[10:1];
        enc_j[6:0] = JAL;
    endfunction

    task automatic check(
        input string           name,
        input logic [IALIGN-1:0] inst_in,
        input inst_fmt_t        fmt_in,
        input logic [XLEN-1:0] expected
    );
        begin
            inst = inst_in;
            inst_fmt = fmt_in;
            #1;

            tests_run++;
            if (imm !== expected) begin
                tests_failed++;
                $fatal(1, "%s: expected 0x%016x, got 0x%016x",
                       name, expected, imm);
            end
        end
    endtask

    initial begin
        tests_run = 0;
        tests_failed = 0;

        check("R format has no immediate",
              32'hffff_ffff, IMM_R, '0);

        check("I format positive immediate",
              enc_i(12'h123), IMM_I, 64'h0000_0000_0000_0123);
        check("I format sign extends negative immediate",
              enc_i(12'hf80), IMM_I, 64'hffff_ffff_ffff_ff80);

        check("S format joins split immediate",
              enc_s(12'h2a5), IMM_S, 64'h0000_0000_0000_02a5);
        check("S format sign extends negative immediate",
              enc_s(12'hfe4), IMM_S, 64'hffff_ffff_ffff_ffe4);

        check("B format joins split offset and clears bit zero",
              enc_b(13'h018), IMM_B, 64'h0000_0000_0000_0018);
        check("B format sign extends negative offset",
              enc_b(13'h1ff0), IMM_B, 64'hffff_ffff_ffff_fff0);

        check("U format shifts upper immediate into place",
              enc_u(20'habcde), IMM_U, 64'hffff_ffff_abcde_000);

        check("J format joins scattered offset and clears bit zero",
              enc_j(21'h00abc), IMM_J, 64'h0000_0000_0000_0abc);
        check("J format sign extends negative offset",
              enc_j(21'h1ff800), IMM_J, 64'hffff_ffff_ffff_f800);

        if (tests_failed == 0) begin
            $display("tb_immediate_gen: all %0d tests passed", tests_run);
            $finish;
        end else begin
            $fatal(1, "tb_immediate_gen: %0d of %0d tests failed",
                   tests_failed, tests_run);
        end
    end
endmodule : tb_immediate_gen
