`timescale 1ns/1ps

import riscv::*;

module tb_regfile;
    logic                  clk;
    logic                  rst_n;
    ctrl_t                 ctrl;
    logic [XLEN-1:0]       alu_data;
    logic [XLEN-1:0]       mem_data;
    logic [XLEN-1:0]       pc;
    logic [XLEN-1:0]       imm;
    logic [XLEN-1:0]       rs1_data;
    logic [XLEN-1:0]       rs2_data;

    int tests_run;
    int tests_failed;

    regfile dut (
        .clk(clk),
        .rst_n(rst_n),
        .ctrl_i(ctrl),
        .alu_i(alu_data),
        .mem_i(mem_data),
        .pc_i(pc),
        .imm_i(imm),
        .rs1_data_o(rs1_data),
        .rs2_data_o(rs2_data)
    );

    always #5 clk = ~clk;

    task automatic write_reg(
        input logic [REG_ADDR_W-1:0] addr,
        input logic [XLEN-1:0]       data,
        input logic                  write_en
    );
        begin
            ctrl.rd_addr = addr;
            ctrl.wb_sel = WB_ALU;
            ctrl.reg_write = write_en;
            alu_data = data;
            @(posedge clk);
            #1;
            ctrl.reg_write = 1'b0;
        end
    endtask

    task automatic check_read(
        input string                 name,
        input logic [REG_ADDR_W-1:0] rs1,
        input logic [REG_ADDR_W-1:0] rs2,
        input logic [XLEN-1:0]       expected_rs1,
        input logic [XLEN-1:0]       expected_rs2
    );
        begin
            ctrl.rs1_addr = rs1;
            ctrl.rs2_addr = rs2;
            #1;

            tests_run++;
            if (rs1_data !== expected_rs1) begin
                tests_failed++;
                $error("%s rs1: expected 0x%08x, got 0x%08x",
                       name, expected_rs1, rs1_data);
            end
            if (rs2_data !== expected_rs2) begin
                tests_failed++;
                $error("%s rs2: expected 0x%08x, got 0x%08x",
                       name, expected_rs2, rs2_data);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b1;
        ctrl = '0;
        ctrl.wb_sel = WB_ALU;
        alu_data = '0;
        mem_data = '0;
        pc = '0;
        imm = '0;
        tests_run = 0;
        tests_failed = 0;

        rst_n = 1'b0;
        #1;
        check_read("reset keeps x0 zero", X0, X0, '0, '0);

        rst_n = 1'b1;
        @(posedge clk);
        #1;
        check_read("reset clears general registers", 5'd1, 5'd2, '0, '0);

        write_reg(5'd1, 32'h1234_5678, 1'b1);
        check_read("write x1 read on rs1", 5'd1, 5'd2, 32'h1234_5678, '0);

        write_reg(5'd2, 32'hcafe_babe, 1'b1);
        check_read("two independent read ports", 5'd1, 5'd2,
                   32'h1234_5678, 32'hcafe_babe);

        write_reg(5'd3, 32'hdead_beef, 1'b0);
        check_read("disabled write does not update register", 5'd3, 5'd1,
                   '0, 32'h1234_5678);

        write_reg(X0, 32'hffff_ffff, 1'b1);
        check_read("writes to x0 are ignored", X0, 5'd1,
                   '0, 32'h1234_5678);

        write_reg(5'd1, 32'h8765_4321, 1'b1);
        check_read("overwrite existing register", 5'd1, 5'd2,
                   32'h8765_4321, 32'hcafe_babe);

        ctrl.rs1_addr = 5'd4;
        ctrl.rs2_addr = 5'd1;
        ctrl.rd_addr = 5'd4;
        ctrl.wb_sel = WB_ALU;
        ctrl.reg_write = 1'b1;
        alu_data = 32'h0bad_f00d;
        #1;
        check_read("same-cycle read before clock sees old value", 5'd4, 5'd1,
                   '0, 32'h8765_4321);
        @(posedge clk);
        #1;
        ctrl.reg_write = 1'b0;
        check_read("read after write clock sees new value", 5'd4, 5'd1,
                   32'h0bad_f00d, 32'h8765_4321);

        rst_n = 1'b0;
        #1;
        check_read("async reset clears written registers", 5'd1, 5'd4,
                   '0, '0);

        if (tests_failed == 0) begin
            $display("tb_regfile: all %0d checks passed", tests_run);
            $finish;
        end

        $fatal(1, "tb_regfile: %0d of %0d checks failed",
               tests_failed, tests_run);
    end
endmodule : tb_regfile
