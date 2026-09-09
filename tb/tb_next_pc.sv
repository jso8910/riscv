`timescale 1ns/1ps

import riscv::*;

module tb_next_pc;
    ctrl_t            ctrl;
    logic [XLEN-1:0]  pc;
    logic [XLEN-1:0]  rs1_data;
    logic [XLEN-1:0]  rs2_data;
    logic [XLEN-1:0]  alu_res;
    logic [XLEN-1:0]  mepc;
    logic [XLEN-1:0]  mtvec;
    trap_t            trap;
    logic [XLEN-1:0]  next_pc_out;
    logic             address_misaligned;

    int tests_run;
    int tests_failed;

    next_pc_unit dut (
        .ctrl_i(ctrl),
        .pc_i(pc),
        .rs1_data_i(rs1_data),
        .rs2_data_i(rs2_data),
        .alu_res_i(alu_res),
        .mepc_i(mepc),
        .mtvec_i(mtvec),
        .trap_i(trap),
        .address_misaligned_o(address_misaligned),
        .next_pc_o(next_pc_out)
    );

    function automatic logic branch_funct3_valid(input logic [2:0] f3);
        case (f3)
            EQ, NE, LT, GE, LTU, GEU : branch_funct3_valid = 1'b1;
            default : branch_funct3_valid = 1'b0;
        endcase
    endfunction

    task automatic check(
        input string            name,
        input logic             branch_in,
        input logic             jal_in,
        input logic             jalr_in,
        input logic [2:0]       f3,
        input logic [XLEN-1:0]  immediate,
        input logic [XLEN-1:0]  pc_in,
        input logic [XLEN-1:0]  rs1,
        input logic [XLEN-1:0]  rs2,
        input logic [XLEN-1:0]  expected
    );
        begin
            ctrl = '0;
            trap = '0;
            ctrl.branch = branch_in && branch_funct3_valid(f3);
            ctrl.jal = jal_in;
            ctrl.jalr = jalr_in;
            case (f3)
                EQ : ctrl.branch_cond = COND_EQ;
                NE : ctrl.branch_cond = COND_NE;
                LT : ctrl.branch_cond = COND_LT;
                GE : ctrl.branch_cond = COND_GE;
                LTU : ctrl.branch_cond = COND_LTU;
                GEU : ctrl.branch_cond = COND_GEU;
                default : ctrl.branch_cond = COND_EQ;
            endcase
            pc = pc_in;
            rs1_data = rs1;
            rs2_data = rs2;
            alu_res = jal_in ? pc_in + immediate :
                      jalr_in ? rs1 + immediate :
                      pc_in + immediate;
            #1;

            tests_run++;
            if (next_pc_out !== expected) begin
                tests_failed++;
                $fatal(1, "%s: expected 0x%016x, got 0x%016x",
                       name, expected, next_pc_out);
            end
        end
    endtask

    initial begin
        tests_run = 0;
        tests_failed = 0;
        mepc = 32'h0000_3000;
        mtvec = 32'h0000_4000;
        trap = '0;

        check("sequential pc",
              1'b0, 1'b0, 1'b0, EQ, 32'd16, 32'h0000_1000,
              32'd0, 32'd0, 32'h0000_1004);

        check("JAL target uses current pc plus immediate",
              1'b0, 1'b1, 1'b0, EQ, 32'd64, 32'h0000_1000,
              32'd0, 32'd0, 32'h0000_1040);
        check("JAL backward target",
              1'b0, 1'b1, 1'b0, EQ, 64'hffff_ffff_ffff_ffc0, 32'h0000_1000,
              32'd0, 32'd0, 32'h0000_0fc0);
        check("JALR target clears bit zero",
              1'b0, 1'b0, 1'b1, EQ, 32'd4, 32'h0000_1000,
              32'h0000_2001, 32'd0, 32'h0000_2004);
        check("JALR supports negative immediate",
              1'b0, 1'b0, 1'b1, EQ, 64'hffff_ffff_ffff_fffc, 32'h0000_1000,
              32'h0000_2003, 32'd0, 32'h0000_1ffe);

        check("BEQ taken",
              1'b1, 1'b0, 1'b0, EQ, 32'd12, 32'h0000_1000,
              32'h1234_5678, 32'h1234_5678, 32'h0000_100c);
        check("BEQ not taken",
              1'b1, 1'b0, 1'b0, EQ, 32'd12, 32'h0000_1000,
              32'h1234_5678, 32'h8765_4321, 32'h0000_1004);
        check("BNE taken",
              1'b1, 1'b0, 1'b0, NE, 32'd12, 32'h0000_1000,
              32'h1234_5678, 32'h8765_4321, 32'h0000_100c);
        check("BNE not taken",
              1'b1, 1'b0, 1'b0, NE, 32'd12, 32'h0000_1000,
              32'h1234_5678, 32'h1234_5678, 32'h0000_1004);

        check("BLT signed negative less than positive",
              1'b1, 1'b0, 1'b0, LT, 32'd8, 32'h0000_1000,
              64'hffff_ffff_ffff_ffff, 32'd1, 32'h0000_1008);
        check("BLT signed positive not less than negative",
              1'b1, 1'b0, 1'b0, LT, 32'd8, 32'h0000_1000,
              32'd1, 64'hffff_ffff_ffff_ffff, 32'h0000_1004);
        check("BGE signed positive greater than negative",
              1'b1, 1'b0, 1'b0, GE, 32'd8, 32'h0000_1000,
              32'd1, 64'hffff_ffff_ffff_ffff, 32'h0000_1008);
        check("BGE signed negative not greater or equal",
              1'b1, 1'b0, 1'b0, GE, 32'd8, 32'h0000_1000,
              64'hffff_ffff_ffff_ffff, 32'd1, 32'h0000_1004);

        check("BLTU zero less than max unsigned",
              1'b1, 1'b0, 1'b0, LTU, 32'd8, 32'h0000_1000,
              32'd0, 64'hffff_ffff_ffff_ffff, 32'h0000_1008);
        check("BLTU max unsigned not less than zero",
              1'b1, 1'b0, 1'b0, LTU, 32'd8, 32'h0000_1000,
              64'hffff_ffff_ffff_ffff, 32'd0, 32'h0000_1004);
        check("BGEU max unsigned greater or equal zero",
              1'b1, 1'b0, 1'b0, GEU, 32'd8, 32'h0000_1000,
              64'hffff_ffff_ffff_ffff, 32'd0, 32'h0000_1008);
        check("BGEU zero not greater or equal max unsigned",
              1'b1, 1'b0, 1'b0, GEU, 32'd8, 32'h0000_1000,
              32'd0, 64'hffff_ffff_ffff_ffff, 32'h0000_1004);

        check("invalid branch funct3 falls through",
              1'b1, 1'b0, 1'b0, 3'b010, 32'd8, 32'h0000_1000,
              32'd0, 32'd0, 32'h0000_1004);
        check("JAL has priority over branch",
              1'b1, 1'b1, 1'b0, EQ, 32'd20, 32'h0000_1000,
              32'd1, 32'd2, 32'h0000_1014);
        check("JAL has priority over JALR",
              1'b0, 1'b1, 1'b1, EQ, 32'd20, 32'h0000_1000,
              32'h0000_2001, 32'd0, 32'h0000_1014);

        ctrl = '0;
        trap = '0;
        pc = 32'h0000_1000;
        rs1_data = '0;
        rs2_data = '0;
        alu_res = '0;
        #1;
        tests_run++;
        if (address_misaligned !== 1'b0) begin
            tests_failed++;
            $fatal(1, "sequential four-byte-aligned PC must not be misaligned");
        end

        ctrl = '0;
        ctrl.jal = 1'b1;
        pc = 32'h0000_1000;
        alu_res = 32'h0000_1002;
        #1;
        tests_run++;
        if (address_misaligned !== 1'b1) begin
            tests_failed++;
            $fatal(1, "taken control transfer to a two-byte-aligned target must be misaligned");
        end

        if (tests_failed == 0) begin
            $display("tb_next_pc: all %0d tests passed", tests_run);
            $finish;
        end else begin
            $fatal(1, "tb_next_pc: %0d of %0d tests failed", tests_failed, tests_run);
        end
    end
endmodule : tb_next_pc
