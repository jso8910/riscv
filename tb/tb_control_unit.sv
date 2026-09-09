`timescale 1ns/1ps

import riscv::*;

module tb_control_unit;
    logic [IALIGN-1:0] inst;
    logic [XLEN-1:0] imm;
    ctrl_t ctrl;
    int tests_run;
    int tests_failed;

    control_unit dut (
        .inst_i(inst),
        .imm_o(imm),
        .ctrl_o(ctrl)
    );

    function automatic logic [31:0] csr_inst(
        input logic [11:0] csr,
        input logic [4:0] rs1_or_uimm,
        input logic [2:0] funct3,
        input logic [4:0] rd
    );
        return {csr, rs1_or_uimm, funct3, rd, SYSTEM};
    endfunction

    task automatic check(input string name, input logic condition);
        begin
            tests_run++;
            if (!condition) begin
                tests_failed++;
                $fatal(1, "%s", name);
            end
        end
    endtask

    task automatic drive(input logic [31:0] instruction);
        begin
            inst = instruction;
            #1;
        end
    endtask

    initial begin
        tests_run = 0;
        tests_failed = 0;

        drive(32'h0050_0093); // addi x1, x0, 5
        check("ADDI selects an immediate ALU operation",
              ctrl.reg_write && ctrl.wb_sel == WB_ALU && ctrl.alu_sel_imm
              && ctrl.alu_op == ALU_ADD && imm == 32'd5);

        drive(32'h0041_2083); // lw x1, 4(x2)
        check("LW selects a signed word load and memory writeback",
              ctrl.mem_read && !ctrl.mem_write && ctrl.mem_size == MEM_WORD
              && ctrl.mem_signed == MEM_SIGNED && ctrl.reg_write && ctrl.wb_sel == WB_MEM);

        drive(csr_inst(MSTATUS, 5'd0, CSRRS, 5'd1));
        check("CSRRS with rs1=x0 reads but does not write",
              ctrl.csr_read && !ctrl.csr_write && ctrl.csr_wb_sel == WB_SET_BITS
              && ctrl.reg_write && ctrl.wb_sel == WB_CSR);

        drive(csr_inst(MTVEC, 5'd3, CSRRWI, 5'd4));
        check("CSRRWI selects the five-bit immediate operand",
              ctrl.csr_read && ctrl.csr_write && ctrl.csr_imm
              && ctrl.csr_wb_sel == WB_NORMAL);

        drive(32'h3020_0073); // standard MRET encoding
        check("standard MRET decodes as a return through MEPC",
              ctrl.mret && ctrl.branch && ctrl.branch_src == SRC_MEPC && !ctrl.illegal);

        drive(32'h1050_0073); // standard WFI encoding
        check("WFI is a legal no-op",
              !ctrl.illegal && !ctrl.branch && !ctrl.jal && !ctrl.jalr
              && !ctrl.mem_read && !ctrl.mem_write && !ctrl.reg_write
              && !ctrl.csr_read && !ctrl.csr_write);

        drive(32'h0000_10e7); // invalid JALR funct3, with rd=x1
        check("invalid JALR has no side effects",
              ctrl.illegal && !ctrl.branch && !ctrl.jal && !ctrl.jalr
              && !ctrl.mem_read && !ctrl.mem_write && !ctrl.reg_write
              && !ctrl.csr_read && !ctrl.csr_write);

        drive(32'h0000_2063); // invalid BRANCH funct3
        check("invalid branch has no side effects",
              ctrl.illegal && !ctrl.branch && !ctrl.jal && !ctrl.jalr
              && !ctrl.mem_read && !ctrl.mem_write && !ctrl.reg_write
              && !ctrl.csr_read && !ctrl.csr_write);

        drive(32'h0000_7083); // invalid LOAD funct3, with rd=x1
        check("invalid load has no memory or register side effect",
              ctrl.illegal && !ctrl.mem_read && !ctrl.mem_write && !ctrl.reg_write);

        drive(32'h0000_4023); // invalid STORE funct3
        check("invalid store has no memory side effect",
              ctrl.illegal && !ctrl.mem_read && !ctrl.mem_write && !ctrl.reg_write);

        drive(32'h4000_1093); // invalid SLLI funct7, with rd=x1
        check("invalid ALU instruction has no register side effect",
              ctrl.illegal && !ctrl.mem_read && !ctrl.mem_write && !ctrl.reg_write);

        drive(32'h02f1_1093); // slli x1, x2, 47
        check("RV64 SLLI accepts a six-bit shift amount",
              !ctrl.illegal && ctrl.reg_write && ctrl.wb_sel == WB_ALU
              && ctrl.alu_sel_imm && !ctrl.alu_word_op && ctrl.alu_op == ALU_SLL);

        drive(32'h02f1_5093); // srli x1, x2, 47
        check("RV64 SRLI accepts a six-bit shift amount",
              !ctrl.illegal && ctrl.reg_write && ctrl.wb_sel == WB_ALU
              && ctrl.alu_sel_imm && !ctrl.alu_word_op && ctrl.alu_op == ALU_SRL);

        drive(32'h42f1_5093); // srai x1, x2, 47
        check("RV64 SRAI accepts a six-bit shift amount",
              !ctrl.illegal && ctrl.reg_write && ctrl.wb_sel == WB_ALU
              && ctrl.alu_sel_imm && !ctrl.alu_word_op && ctrl.alu_op == ALU_SRA);

        drive(32'h0201_10b3); // invalid SLL funct7, with rd=x1
        check("invalid register SLL funct7 has no register side effect",
              ctrl.illegal && !ctrl.mem_read && !ctrl.mem_write && !ctrl.reg_write);

        drive(32'h0201_50b3); // invalid SRL funct7, with rd=x1
        check("invalid register SRL funct7 has no register side effect",
              ctrl.illegal && !ctrl.mem_read && !ctrl.mem_write && !ctrl.reg_write);

        drive(32'h4201_50b3); // invalid SRA funct7, with rd=x1
        check("invalid register SRA funct7 has no register side effect",
              ctrl.illegal && !ctrl.mem_read && !ctrl.mem_write && !ctrl.reg_write);

        if (tests_failed == 0) begin
            $display("tb_control_unit: all %0d checks passed", tests_run);
            $finish;
        end else begin
            $fatal(1, "tb_control_unit: %0d of %0d checks failed", tests_failed, tests_run);
        end
    end
endmodule : tb_control_unit
