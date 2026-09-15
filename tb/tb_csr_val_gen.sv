`timescale 1ns/1ps
import riscv::*;

module tb_csr_val_gen;
    ctrl_t ctrl;
    logic [XLEN-1:0] rs1_data, csr_val, csr_data;
    int tests_run, tests_failed;

    csr_val_gen dut (.ctrl_i(ctrl), .rs1_data_i(rs1_data), .csr_val_i(csr_val), .csr_data_o(csr_data));

    task automatic check(input string name, input logic [XLEN-1:0] expected);
        begin
            #1; tests_run++;
            if (csr_data !== expected) begin
                tests_failed++;
                $fatal(1, "%s: expected %h, got %h", name, expected, csr_data);
            end
        end
    endtask

    initial begin
        tests_run = 0; tests_failed = 0;
        ctrl = '0; rs1_data = 64'h1234; csr_val = 64'h00f0;
        ctrl.csr_wb_sel = WB_NORMAL;
        check("CSRRW uses rs1", 64'h1234);
        ctrl.csr_imm = 1'b1; ctrl.rs1_addr = 5'd17;
        check("CSRRWI zero-extends uimm", 64'd17);
        ctrl.csr_imm = 1'b0; ctrl.csr_wb_sel = WB_SET_BITS; rs1_data = 64'h0f00;
        check("CSRRS sets requested bits", 64'h0ff0);
        ctrl.csr_wb_sel = WB_CLEAR_BITS; rs1_data = 64'h0030;
        check("CSRRC clears requested bits", 64'h00c0);
        $display("tb_csr_val_gen: all %0d checks passed", tests_run);
        $finish;
    end
endmodule
