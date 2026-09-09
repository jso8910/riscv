`timescale 1ns/1ps

import riscv::*;

module tb_core;
    localparam int SC_WFI          = 0;
    localparam int SC_INVALID_JALR = 1;
    localparam int SC_INVALID_BR   = 2;
    localparam int SC_INVALID_LOAD = 3;
    localparam int SC_INVALID_ST   = 4;
    localparam int SC_INVALID_ALU  = 5;
    localparam int SC_TRAP_MRET    = 6;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [IALIGN-1:0] inst = 32'h0000_0013;
    logic [WWIDTH-1:0] data_mem_data = '0;
    logic [XLEN-1:0] pc;
    logic [WWIDTH/8-1:0] data_mem_we;
    logic [XLEN-1:0] data_mem_addr;
    logic [WWIDTH-1:0] data_mem_write_data;
    int scenario = SC_WFI;
    int tests_run;
    int tests_failed;

    riscv_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .inst_i(inst),
        .data_mem_data_i(data_mem_data),
        .pc_o(pc),
        .data_mem_we_o(data_mem_we),
        .data_mem_addr_o(data_mem_addr),
        .data_mem_data_o(data_mem_write_data)
    );

    always #5 clk = ~clk;

    function automatic logic [31:0] i_inst(
        input logic [11:0] immediate,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );
        return {immediate, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] s_inst(
        input logic [11:0] immediate,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3
    );
        return {immediate[11:5], rs2, rs1, funct3, immediate[4:0], STORE};
    endfunction

    function automatic logic [31:0] csr_inst(
        input logic [11:0] csr,
        input logic [4:0] rs1_or_uimm,
        input logic [2:0] funct3,
        input logic [4:0] rd
    );
        return {csr, rs1_or_uimm, funct3, rd, SYSTEM};
    endfunction

    // A deliberately tiny instruction source. Each scenario is reset before execution.
    function automatic logic [31:0] instruction_at(
        input int selected_scenario,
        input logic [XLEN-1:0] address
    );
        instruction_at = 32'h0000_0013; // addi x0, x0, 0
        case (selected_scenario)
            SC_WFI: begin
                if (address == RESET_PC)
                    instruction_at = WFI;
            end
            SC_INVALID_JALR: begin
                case (address)
                    RESET_PC:     instruction_at = i_inst(12'd5, X0, ADD_SUB, 5'd1, OP_IMM);
                    RESET_PC + 4: instruction_at = i_inst(12'd64, X0, ADD_SUB, 5'd2, OP_IMM);
                    RESET_PC + 8: instruction_at = i_inst('0, 5'd2, 3'b001, 5'd1, JALR);
                    default: ;
                endcase
            end
            SC_INVALID_BR: begin
                case (address)
                    RESET_PC:     instruction_at = i_inst(12'd5, X0, ADD_SUB, 5'd1, OP_IMM);
                    RESET_PC + 4: instruction_at = 32'h0000_2063; // invalid BRANCH funct3
                    default: ;
                endcase
            end
            SC_INVALID_LOAD: begin
                case (address)
                    RESET_PC:     instruction_at = i_inst(12'd5, X0, ADD_SUB, 5'd1, OP_IMM);
                    RESET_PC + 4: instruction_at = i_inst('0, X0, 3'b111, 5'd1, LOAD);
                    default: ;
                endcase
            end
            SC_INVALID_ST: begin
                case (address)
                    RESET_PC:     instruction_at = i_inst(12'h055, X0, ADD_SUB, 5'd2, OP_IMM);
                    RESET_PC + 4: instruction_at = s_inst('0, 5'd2, X0, 3'b100);
                    default: ;
                endcase
            end
            SC_INVALID_ALU: begin
                case (address)
                    RESET_PC:     instruction_at = i_inst(12'd5, X0, ADD_SUB, 5'd1, OP_IMM);
                    // SLLI with imm[11:6]=010000 is reserved in RV64I.
                    RESET_PC + 4: instruction_at = i_inst(12'b0100000_00000, X0, SLL, 5'd1, OP_IMM);
                    default: ;
                endcase
            end
            SC_TRAP_MRET: begin
                case (address)
                    RESET_PC:      instruction_at = i_inst(12'h040, X0, ADD_SUB, 5'd1, OP_IMM);
                    RESET_PC + 4:  instruction_at = csr_inst(MTVEC, 5'd1, CSRRW, X0);
                    RESET_PC + 8:  instruction_at = csr_inst(MSTATUS, 5'd8, CSRRWI, X0);
                    RESET_PC + 12: instruction_at = EBREAK;
                    32'h0000_0040: instruction_at = MRET;
                    default: ;
                endcase
            end
            default: ;
        endcase
    endfunction

    task automatic check(
        input string name,
        input logic condition
    );
        begin
            tests_run++;
            if (!condition) begin
                tests_failed++;
                $fatal(1, "%s", name);
            end
        end
    endtask

    task automatic reset_core(input int selected_scenario);
        begin
            scenario = selected_scenario;
            inst = instruction_at(selected_scenario, RESET_PC);
            rst_n = 1'b0;
            #1;
            @(posedge clk);
            #1;
            rst_n = 1'b1;
            #1;
        end
    endtask

    task automatic step;
        begin
            inst = instruction_at(scenario, pc);
            #1;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic check_illegal_trap(
        input string name,
        input logic [XLEN-1:0] expected_mepc
    );
        begin
            check({name, ": redirects to mtvec"}, pc == RESET_PC);
            check({name, ": writes illegal-instruction mcause"},
                  dut.u_csrfile.mcause == XLEN'(ILLEGAL_INSTRUCTION));
            check({name, ": records the faulting pc in mepc"},
                  dut.u_csrfile.mepc == expected_mepc);
            check({name, ": records zero mtval"}, dut.u_csrfile.mtval == '0);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        data_mem_data = '0;
        scenario = SC_WFI;
        tests_run = 0;
        tests_failed = 0;

        reset_core(SC_WFI);
        step();
        check("WFI advances the PC as a NOP", pc == RESET_PC + 4);
        check("WFI does not trap", dut.u_csrfile.mcause == '0);
        check("WFI retires", dut.u_csrfile.minstret == 64'd1);

        reset_core(SC_INVALID_JALR);
        step();
        step();
        check("invalid JALR setup writes sentinel", dut.u_regfile.regs[1] == 32'd5);
        check("invalid JALR has no data-memory write", data_mem_we == '0);
        step();
        check_illegal_trap("invalid JALR", RESET_PC + 8);
        check("invalid JALR does not overwrite its destination register", dut.u_regfile.regs[1] == 32'd5);

        reset_core(SC_INVALID_BR);
        step();
        check("invalid branch setup writes sentinel", dut.u_regfile.regs[1] == 32'd5);
        step();
        check_illegal_trap("invalid branch", RESET_PC + 4);
        check("invalid branch does not write registers", dut.u_regfile.regs[1] == 32'd5);

        reset_core(SC_INVALID_LOAD);
        step();
        check("invalid load setup writes sentinel", dut.u_regfile.regs[1] == 32'd5);
        check("invalid load has no data-memory write", data_mem_we == '0);
        step();
        check_illegal_trap("invalid load", RESET_PC + 4);
        check("invalid load does not overwrite its destination register", dut.u_regfile.regs[1] == 32'd5);

        reset_core(SC_INVALID_ST);
        step();
        check("invalid store setup writes source register", dut.u_regfile.regs[2] == 32'h55);
        check("invalid store has no data-memory write", data_mem_we == '0);
        step();
        check_illegal_trap("invalid store", RESET_PC + 4);
        check("invalid store never enables a data-memory write", data_mem_we == '0);

        reset_core(SC_INVALID_ALU);
        step();
        check("invalid ALU setup writes sentinel", dut.u_regfile.regs[1] == 32'd5);
        step();
        check_illegal_trap("invalid ALU instruction", RESET_PC + 4);
        check("invalid ALU instruction does not overwrite its destination register", dut.u_regfile.regs[1] == 32'd5);

        reset_core(SC_TRAP_MRET);
        step();
        step();
        step();
        check("CSRRWI enables MIE before the trap", dut.u_csrfile.mstatus[MSTATUS_MIE]);
        step();
        check("trap redirects to programmed mtvec", pc == 32'h0000_0040);
        check("trap entry writes breakpoint mcause", dut.u_csrfile.mcause == XLEN'(BREAKPOINT));
        check("trap entry writes mepc", dut.u_csrfile.mepc == RESET_PC + 12);
        check("trap entry writes mtval", dut.u_csrfile.mtval == '0);
        check("trap entry clears MIE", !dut.u_csrfile.mstatus[MSTATUS_MIE]);
        check("trap entry saves MIE in MPIE", dut.u_csrfile.mstatus[MSTATUS_MPIE]);
        check("trap entry saves M privilege in MPP",
              dut.u_csrfile.mstatus[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] == M_MODE);
        step();
        check("MRET returns to mepc", pc == RESET_PC + 12);
        check("MRET restores MIE", dut.u_csrfile.mstatus[MSTATUS_MIE]);
        check("MRET sets MPIE", dut.u_csrfile.mstatus[MSTATUS_MPIE]);
        check("MRET restores MPP to M for this M-only core",
              dut.u_csrfile.mstatus[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] == M_MODE);

        if (tests_failed == 0) begin
            $display("tb_core: all %0d checks passed", tests_run);
            $finish;
        end else begin
            $fatal(1, "tb_core: %0d of %0d checks failed", tests_failed, tests_run);
        end
    end
endmodule : tb_core
