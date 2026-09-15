`timescale 1ns/1ps
import riscv::*;

module tb_forwarding_hazard;
    ctrl_t ex_ctrl, mem_ctrl, wb_ctrl, id_ctrl;
    logic mem_valid, wb_valid, ex_valid, load_use_hazard, late_csr_use_hazard, csr_interlock_hazard;
    logic [XLEN-1:0] rs1_raw, rs2_raw, csr_raw, mem_rd, wb_rd;
    logic [XLEN-1:0] rs1_out, rs2_out, csr_out;
    int tests_run, tests_failed;

    forwarding_unit forwarding (
        .ex_ctrl_i(ex_ctrl), .ex_rs1_data_raw_i(rs1_raw), .ex_rs2_data_raw_i(rs2_raw),
        .ex_csr_data_raw_i(csr_raw), .mem_valid_i(mem_valid), .mem_ctrl_i(mem_ctrl),
        .mem_rd_data_i(mem_rd), .wb_valid_i(wb_valid), .wb_ctrl_i(wb_ctrl), .wb_rd_data_i(wb_rd),
        .ex_rs1_data_o(rs1_out), .ex_rs2_data_o(rs2_out), .ex_csr_data_o(csr_out)
    );
    hazard_unit hazard (.ex_valid_i(ex_valid), .mem_valid_i(mem_valid), .wb_valid_i(wb_valid),
                        .id_ctrl_i(id_ctrl), .ex_ctrl_i(ex_ctrl), .mem_ctrl_i(mem_ctrl), .wb_ctrl_i(wb_ctrl),
                        .load_use_hazard_o(load_use_hazard), .late_csr_use_hazard_o(late_csr_use_hazard),
                        .csr_interlock_hazard_o(csr_interlock_hazard));

    task automatic check(input string name, input logic condition);
        begin #1; tests_run++; if (!condition) begin tests_failed++; $fatal(1, "%s", name); end end
    endtask

    initial begin
        tests_run = 0; tests_failed = 0;
        ex_ctrl = '0; mem_ctrl = '0; wb_ctrl = '0; id_ctrl = '0;
        mem_valid = 1; wb_valid = 1; ex_valid = 1;
        rs1_raw = 64'h11; rs2_raw = 64'h22; csr_raw = 64'h33;
        mem_rd = 64'haa; wb_rd = 64'hbb;

        ex_ctrl.rs1_addr = 5; mem_ctrl.rd_addr = 5; mem_ctrl.reg_write = 1;
        mem_ctrl.wb_sel = WB_ALU;
        #1; check("MEM forwards producer rd to rs1", rs1_out == mem_rd);
        ex_ctrl.rs2_addr = 6; wb_ctrl.rd_addr = 6; wb_ctrl.reg_write = 1;
        #1; check("WB forwards producer rd to rs2", rs2_out == wb_rd);
        mem_ctrl.wb_sel = WB_MEM; ex_ctrl.rs1_addr = 5;
        #1; check("load is not forwarded from MEM", rs1_out == rs1_raw);
        mem_ctrl.wb_sel = WB_ALU; mem_ctrl.rd_addr = X0;
        #1; check("x0 is never forwarded", rs1_out == rs1_raw);
        ex_ctrl.csr_addr = MSTATUS; mem_ctrl.csr_addr = MSTATUS; mem_ctrl.csr_write = 1;
        #1; check("CSR value is not forwarded", csr_out == csr_raw);
        mem_valid = 0;
        #1; check("invalid MEM leaves CSR value unchanged", csr_out == csr_raw);

        ex_ctrl = '0; id_ctrl = '0; ex_valid = 1;
        ex_ctrl.reg_write = 1; ex_ctrl.wb_sel = WB_MEM; ex_ctrl.rd_addr = 7;
        id_ctrl.reg_write = 1; id_ctrl.wb_sel = WB_ALU; id_ctrl.op1_src = RS1; id_ctrl.rs1_addr = 7;
        #1; check("load-use on rs1 stalls", load_use_hazard);
        id_ctrl.rs1_addr = 1; id_ctrl.rs2_addr = 7; id_ctrl.alu_sel_imm = 1;
        #1; check("immediate rs2 field does not stall", !load_use_hazard);
        id_ctrl.mem_write = 1;
        #1; check("store data dependency stalls", load_use_hazard);
        id_ctrl.mem_write = 0; id_ctrl.rs1_addr = 7; id_ctrl.reg_write = 1; id_ctrl.wb_sel = WB_ALU;
        id_ctrl.op1_src = RS1; ex_ctrl.wb_sel = WB_CSR; ex_ctrl.csr_addr = CYCLE;
        #1; check("late CSR result stalls an immediate consumer", late_csr_use_hazard);
        ex_ctrl.csr_addr = MSTATUS;
        #1; check("ordinary CSR result does not stall", !late_csr_use_hazard);
        ex_ctrl = '0; mem_ctrl = '0; wb_ctrl = '0; id_ctrl = '0;
        ex_valid = 1; mem_valid = 0; wb_valid = 0;
        ex_ctrl.csr_write = 1; ex_ctrl.csr_addr = MSTATUS;
        id_ctrl.csr_read = 1; id_ctrl.csr_addr = MSTATUS;
        #1; check("EX CSR write interlocks a CSR read", csr_interlock_hazard);
        id_ctrl.csr_addr = SSTATUS;
        #1; check("mstatus and sstatus share an interlock", csr_interlock_hazard);
        id_ctrl.csr_addr = MIE;
        #1; check("unrelated CSR state does not interlock", !csr_interlock_hazard);
        ex_valid = 0; mem_valid = 1; mem_ctrl.csr_write = 1; mem_ctrl.csr_addr = SSTATUS;
        id_ctrl.csr_addr = MSTATUS;
        #1; check("MEM CSR write interlocks an alias read", csr_interlock_hazard);
        mem_valid = 0; wb_valid = 1; wb_ctrl.csr_write = 1; wb_ctrl.csr_addr = MSTATUS;
        #1; check("WB CSR write remains interlocked", csr_interlock_hazard);
        id_ctrl.csr_read = 0;
        #1; check("CSR writes without a read do not interlock", !csr_interlock_hazard);
        ex_valid = 0;
        #1; check("invalid EX load cannot stall decode", !load_use_hazard);
        $display("tb_forwarding_hazard: all %0d checks passed", tests_run);
        $finish;
    end
endmodule
