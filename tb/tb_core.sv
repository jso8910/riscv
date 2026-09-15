`timescale 1ns/1ps

import riscv::*;

// Core smoke test using the post-MMU instruction-memory interface.  Translation
// is Bare in reset M-mode, so the instruction address is also the program PC.
module tb_core;
    logic clk, rst_n;
    logic [WWIDTH-1:0] inst_mem_data, data_mem_data;
    logic [XLEN-1:0] time_i, inst_mem_addr, data_mem_addr, data_mem_write_data;
    logic [WWIDTH/8-1:0] data_mem_we;
    logic mtime_we;
    logic saw_store;
    logic [XLEN-1:0] store_addr, store_data;
    logic saw_cycle, saw_time, saw_instret, saw_mcycle, saw_minstret, saw_mcycle_write,
          sample_mcycle_write_result;
    logic [XLEN-1:0] cycle_value, time_value, instret_value, mcycle_value, minstret_value,
                     mcycle_value_before_write, mcycle_value_after_write;
    int tests_run, tests_failed;

    riscv_core dut (
        .clk(clk), .rst_n(rst_n), .inst_mem_data_i(inst_mem_data),
        .data_mem_data_i(data_mem_data), .time_i(time_i),
        .inst_mem_addr_o(inst_mem_addr), .data_mem_we_o(data_mem_we),
        .data_mem_addr_o(data_mem_addr), .data_mem_data_o(data_mem_write_data),
        .mtime_we_o(mtime_we)
    );

    always #5 clk = ~clk;

    always_comb begin
        inst_mem_data = '0;
        case (inst_mem_addr)
            RESET_PC:      inst_mem_data[31:0] = 32'h0100_0093; // addi x1, x0, 16
            RESET_PC + 4:  inst_mem_data[31:0] = 32'h0000_b103; // ld x2, 0(x1)
            RESET_PC + 8:  inst_mem_data[31:0] = 32'h0011_0193; // addi x3, x2, 1
            RESET_PC + 12: inst_mem_data[31:0] = 32'h0031_8463; // beq x3, x3, +8
            RESET_PC + 16: inst_mem_data[31:0] = 32'h0630_0213; // wrong path: addi x4, x0, 99
            RESET_PC + 20: inst_mem_data[31:0] = 32'h0030_b423; // sd x3, 8(x1)
            RESET_PC + 24: inst_mem_data[31:0] = 32'h0050_0293; // addi x5, x0, 5
            RESET_PC + 28: inst_mem_data[31:0] = 32'h3000_2373; // csrrs x6, mstatus, x0
            RESET_PC + 32: inst_mem_data[31:0] = 32'h0013_0393; // addi x7, x6, 1
            RESET_PC + 36: inst_mem_data[31:0] = 32'hc000_2473; // csrrs x8, cycle, x0
            RESET_PC + 40: inst_mem_data[31:0] = 32'h0014_0493; // addi x9, x8, 1
            RESET_PC + 44: inst_mem_data[31:0] = 32'hc010_2573; // csrrs x10, time, x0
            RESET_PC + 48: inst_mem_data[31:0] = RISCV_NOP;
            RESET_PC + 52: inst_mem_data[31:0] = 32'h0015_0593; // addi x11, x10, 1
            RESET_PC + 56: inst_mem_data[31:0] = 32'hc020_2673; // csrrs x12, instret, x0
            RESET_PC + 60: inst_mem_data[31:0] = RISCV_NOP;
            RESET_PC + 64: inst_mem_data[31:0] = RISCV_NOP;
            RESET_PC + 68: inst_mem_data[31:0] = 32'h0016_0693; // addi x13, x12, 1
            RESET_PC + 72: inst_mem_data[31:0] = 32'hb000_2773; // csrrs x14, mcycle, x0
            RESET_PC + 76: inst_mem_data[31:0] = 32'h0017_0793; // addi x15, x14, 1
            RESET_PC + 80: inst_mem_data[31:0] = 32'hb020_2873; // csrrs x16, minstret, x0
            RESET_PC + 84: inst_mem_data[31:0] = RISCV_NOP;
            RESET_PC + 88: inst_mem_data[31:0] = 32'h0018_0893; // addi x17, x16, 1
            RESET_PC + 92: inst_mem_data[31:0] = 32'hb000_9973; // csrrw x18, mcycle, x1
            RESET_PC + 96: inst_mem_data[31:0] = 32'h0019_0993; // addi x19, x18, 1
            default:       inst_mem_data[31:0] = RISCV_NOP;
        endcase
        data_mem_data = data_mem_addr == 64'd16 ? 64'd41 : '0;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            saw_store <= 1'b0;
            store_addr <= '0;
            store_data <= '0;
            time_i <= '0;
            saw_cycle <= 1'b0;
            saw_time <= 1'b0;
            saw_instret <= 1'b0;
            saw_mcycle <= 1'b0;
            saw_minstret <= 1'b0;
            saw_mcycle_write <= 1'b0;
            sample_mcycle_write_result <= 1'b0;
        end else if (data_mem_we != '0) begin
            saw_store <= 1'b1;
            store_addr <= data_mem_addr;
            store_data <= data_mem_write_data;
        end
        if (rst_n) begin
            time_i <= time_i + XLEN'(1);
            if (sample_mcycle_write_result) begin
                mcycle_value_after_write <= dut.u_csrfile.mcycle;
                sample_mcycle_write_result <= 1'b0;
            end
            if (dut.wb_retire && dut.wb_ctrl.wb_sel == WB_CSR) begin
                case (dut.wb_ctrl.csr_addr)
                    CYCLE: begin saw_cycle <= 1'b1; cycle_value <= dut.u_csrfile.mcycle; end
                    TIME: begin saw_time <= 1'b1; time_value <= time_i; end
                    INSTRET: begin saw_instret <= 1'b1; instret_value <= dut.u_csrfile.minstret; end
                    MCYCLE: begin
                        if (dut.wb_ctrl.csr_write) begin
                            saw_mcycle_write <= 1'b1;
                            sample_mcycle_write_result <= 1'b1;
                            mcycle_value_before_write <= dut.u_csrfile.mcycle;
                        end else begin
                            saw_mcycle <= 1'b1;
                            mcycle_value <= dut.u_csrfile.mcycle;
                        end
                    end
                    MINSTRET: begin saw_minstret <= 1'b1; minstret_value <= dut.u_csrfile.minstret; end
                    default: ;
                endcase
            end
        end
    end

    task automatic check(input string name, input logic condition);
        begin
            tests_run++;
            if (!condition) begin
                tests_failed++;
                $fatal(1, "%s", name);
            end
        end
    endtask

    initial begin
        clk = 0;
        rst_n = 0;
        time_i = '0;
        tests_run = 0;
        tests_failed = 0;

        repeat (2) @(posedge clk);
        #1;
        check("reset holds the instruction address at RESET_PC", inst_mem_addr == RESET_PC);
        check("reset clears general-purpose registers", dut.u_regfile.regs[1] == '0);

        rst_n = 1;
        repeat (80) @(posedge clk);
        #1;
        check("base-address instruction retires", dut.u_regfile.regs[1] == 64'd16);
        check("load result reaches WB", dut.u_regfile.regs[2] == 64'd41);
        check("load-use consumer receives forwarded WB data", dut.u_regfile.regs[3] == 64'd42);
        check("taken branch discards its sequential wrong-path instruction", dut.u_regfile.regs[4] == '0);
        check("branch target executes after recovery", dut.u_regfile.regs[5] == 64'd5);
        check("store commits with forwarded source data", saw_store && store_addr == 64'd24 && store_data == 64'd42);
        check("ordinary CSR result is available without a late interlock", dut.u_regfile.regs[6] == MSTATUS_VAL);
        check("ordinary CSR result forwards to its immediate consumer", dut.u_regfile.regs[7] == MSTATUS_VAL + 1);
        check("cycle is sampled in WB", saw_cycle && dut.u_regfile.regs[8] == cycle_value);
        check("cycle result reaches an immediate consumer", dut.u_regfile.regs[9] == cycle_value + 1);
        check("time is sampled in WB", saw_time && dut.u_regfile.regs[10] == time_value);
        check("time result reaches a one-instruction-delayed consumer", dut.u_regfile.regs[11] == time_value + 1);
        check("instret is sampled before its own retirement", saw_instret && dut.u_regfile.regs[12] == instret_value);
        check("instret result reaches a two-instruction-delayed consumer", dut.u_regfile.regs[13] == instret_value + 1);
        check("mcycle is sampled in WB", saw_mcycle && dut.u_regfile.regs[14] == mcycle_value);
        check("mcycle result reaches an immediate consumer", dut.u_regfile.regs[15] == mcycle_value + 1);
        check("minstret is sampled before its own retirement", saw_minstret && dut.u_regfile.regs[16] == minstret_value);
        check("minstret result reaches a one-instruction-delayed consumer", dut.u_regfile.regs[17] == minstret_value + 1);
        check("mcycle read-modify-write returns the WB snapshot", saw_mcycle_write && dut.u_regfile.regs[18] == mcycle_value_before_write);
        check("mcycle write result reaches an immediate consumer", dut.u_regfile.regs[19] == mcycle_value_before_write + 1);
        check("mcycle read-modify-write uses the carried source operand", mcycle_value_after_write == 64'd16);
        check("retirement advances across hazards and branch recovery", dut.u_csrfile.minstret >= 64'd6);

        if (tests_failed == 0) begin
            $display("tb_core: all %0d checks passed", tests_run);
            $finish;
        end else
            $fatal(1, "tb_core: %0d of %0d checks failed", tests_failed, tests_run);
    end
endmodule : tb_core
