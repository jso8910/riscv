`timescale 1ns/1ps
import riscv::*;

module tb_forwarding_hazard;
    ctrl_t ex1_ctrl, ex2_ctrl, ex3_ctrl, mem_ctrl, wb_ctrl, id_ctrl;
    logic ex1_valid, ex2_valid, ex3_valid, mem_valid, wb_valid;
    logic load_use_hazard, mul_use_hazard, late_csr_use_hazard, csr_interlock_hazard;
    logic [XLEN-1:0] rs1_raw, rs2_raw, csr_raw, ex2_rd, ex3_rd, mem_rd, wb_rd;
    logic [XLEN-1:0] rs1_out, rs2_out, csr_out;
    int tests_run, tests_failed;

    forwarding_unit forwarding (
        .ex_ctrl_i(ex1_ctrl), .ex_rs1_data_raw_i(rs1_raw), .ex_rs2_data_raw_i(rs2_raw),
        .ex_csr_data_raw_i(csr_raw),
        .ex2_valid_i(ex2_valid), .ex2_ctrl_i(ex2_ctrl), .ex2_rd_data_i(ex2_rd),
        .ex3_valid_i(ex3_valid), .ex3_ctrl_i(ex3_ctrl), .ex3_rd_data_i(ex3_rd),
        .mem_valid_i(mem_valid), .mem_ctrl_i(mem_ctrl), .mem_rd_data_i(mem_rd),
        .wb_valid_i(wb_valid), .wb_ctrl_i(wb_ctrl), .wb_rd_data_i(wb_rd),
        .ex_rs1_data_o(rs1_out), .ex_rs2_data_o(rs2_out), .ex_csr_data_o(csr_out)
    );

    hazard_unit hazard (
        .ex1_valid_i(ex1_valid), .ex2_valid_i(ex2_valid), .ex3_valid_i(ex3_valid),
        .mem_valid_i(mem_valid), .wb_valid_i(wb_valid), .id_ctrl_i(id_ctrl),
        .ex1_ctrl_i(ex1_ctrl), .ex2_ctrl_i(ex2_ctrl), .ex3_ctrl_i(ex3_ctrl),
        .mem_ctrl_i(mem_ctrl), .wb_ctrl_i(wb_ctrl), .load_use_hazard_o(load_use_hazard),
        .mul_use_hazard_o(mul_use_hazard), .late_csr_use_hazard_o(late_csr_use_hazard),
        .csr_interlock_hazard_o(csr_interlock_hazard)
    );

    task automatic check(input string name, input logic condition);
        begin
            tests_run++;
            if (!condition) begin
                tests_failed++;
                $fatal(1, "%s", name);
            end
        end
    endtask

    task automatic clear_producers;
        begin
            ex1_ctrl = '0;
            ex2_ctrl = '0;
            ex3_ctrl = '0;
            mem_ctrl = '0;
            wb_ctrl = '0;
            ex1_valid = 0;
            ex2_valid = 0;
            ex3_valid = 0;
            mem_valid = 0;
            wb_valid = 0;
        end
    endtask

    task automatic configure_alu_producer(ref ctrl_t ctrl, input logic [REG_ADDR_W-1:0] rd);
        begin
            ctrl.reg_write = 1;
            ctrl.wb_sel = WB_ALU;
            ctrl.rd_addr = rd;
        end
    endtask

    initial begin
        tests_run = 0;
        tests_failed = 0;
        clear_producers();
        id_ctrl = '0;
        rs1_raw = 64'h11;
        rs2_raw = 64'h22;
        csr_raw = 64'h33;
        ex2_rd = 64'h22;
        ex3_rd = 64'h33;
        mem_rd = 64'h44;
        wb_rd = 64'h55;

        // EX2 is the newest useful producer for an EX1 consumer.
        ex1_ctrl.rs1_addr = 5;
        configure_alu_producer(ex2_ctrl, 5);
        configure_alu_producer(ex3_ctrl, 5);
        configure_alu_producer(mem_ctrl, 5);
        configure_alu_producer(wb_ctrl, 5);
        ex2_valid = 1;
        ex3_valid = 1;
        mem_valid = 1;
        wb_valid = 1;
        #1; check("EX2 forwarding has highest priority", rs1_out == ex2_rd);
        ex2_valid = 0;
        #1; check("EX3 forwarding follows EX2", rs1_out == ex3_rd);
        ex3_valid = 0;
        #1; check("MEM forwarding follows EX3", rs1_out == mem_rd);
        mem_valid = 0;
        #1; check("WB forwarding follows MEM", rs1_out == wb_rd);

        clear_producers();
        ex1_ctrl.rs2_addr = 6;
        configure_alu_producer(ex2_ctrl, 6);
        ex2_valid = 1;
        #1; check("EX2 forwards producer rd to rs2", rs2_out == ex2_rd);
        ex2_ctrl.mul_op = MUL;
        configure_alu_producer(ex3_ctrl, 6);
        ex3_valid = 1;
        #1; check("EX2 multiply data is not forwarded", rs2_out == ex3_rd);
        ex3_valid = 0;
        #1; check("unavailable EX2 multiply leaves raw rs2", rs2_out == rs2_raw);

        clear_producers();
        ex1_ctrl.rs1_addr = 5;
        configure_alu_producer(ex2_ctrl, 5);
        ex2_ctrl.wb_sel = WB_MEM;
        ex2_valid = 1;
        #1; check("load is not forwarded from EX2", rs1_out == rs1_raw);
        ex2_ctrl.wb_sel = WB_ALU;
        ex2_ctrl.rd_addr = X0;
        #1; check("x0 is never forwarded", rs1_out == rs1_raw);
        ex1_ctrl.csr_addr = MSTATUS;
        #1; check("CSR value is not forwarded", csr_out == csr_raw);

        // A load remains unavailable until WB, so every pre-WB stage stalls.
        clear_producers();
        id_ctrl.reg_write = 1;
        id_ctrl.wb_sel = WB_ALU;
        id_ctrl.op1_src = RS1;
        id_ctrl.rs1_addr = 7;
        configure_alu_producer(ex1_ctrl, 7);
        ex1_ctrl.wb_sel = WB_MEM;
        ex1_valid = 1;
        #1; check("EX1 load-use stalls", load_use_hazard);
        ex1_valid = 0;
        configure_alu_producer(ex2_ctrl, 7);
        ex2_ctrl.wb_sel = WB_MEM;
        ex2_valid = 1;
        #1; check("EX2 load-use stalls", load_use_hazard);
        ex2_valid = 0;
        configure_alu_producer(ex3_ctrl, 7);
        ex3_ctrl.wb_sel = WB_MEM;
        ex3_valid = 1;
        #1; check("EX3 load-use stalls", load_use_hazard);
        ex3_valid = 0;
        configure_alu_producer(mem_ctrl, 7);
        mem_ctrl.wb_sel = WB_MEM;
        mem_valid = 1;
        #1; check("MEM load-use stalls", load_use_hazard);
        mem_valid = 0;
        configure_alu_producer(wb_ctrl, 7);
        wb_ctrl.wb_sel = WB_MEM;
        wb_valid = 1;
        #1; check("WB load no longer stalls", !load_use_hazard);

        // A multiply becomes available at EX3, after stalling in EX1 and EX2.
        clear_producers();
        configure_alu_producer(ex1_ctrl, 7);
        ex1_ctrl.mul_op = MUL;
        ex1_valid = 1;
        #1; check("EX1 multiply-use stalls", mul_use_hazard);
        ex1_valid = 0;
        configure_alu_producer(ex2_ctrl, 7);
        ex2_ctrl.mul_op = MUL;
        ex2_valid = 1;
        #1; check("EX2 multiply-use stalls", mul_use_hazard);
        ex2_valid = 0;
        configure_alu_producer(ex3_ctrl, 7);
        ex3_ctrl.mul_op = MUL;
        ex3_valid = 1;
        #1; check("EX3 multiply-use forwards without a stall", !mul_use_hazard);

        // Late CSR results also become usable at WB.
        clear_producers();
        configure_alu_producer(ex1_ctrl, 7);
        ex1_ctrl.wb_sel = WB_CSR;
        ex1_ctrl.csr_addr = CYCLE;
        ex1_valid = 1;
        #1; check("EX1 late CSR-use stalls", late_csr_use_hazard);
        ex1_valid = 0;
        configure_alu_producer(ex2_ctrl, 7);
        ex2_ctrl.wb_sel = WB_CSR;
        ex2_ctrl.csr_addr = CYCLE;
        ex2_valid = 1;
        #1; check("EX2 late CSR-use stalls", late_csr_use_hazard);
        ex2_valid = 0;
        configure_alu_producer(ex3_ctrl, 7);
        ex3_ctrl.wb_sel = WB_CSR;
        ex3_ctrl.csr_addr = CYCLE;
        ex3_valid = 1;
        #1; check("EX3 late CSR-use stalls", late_csr_use_hazard);
        ex3_valid = 0;
        configure_alu_producer(mem_ctrl, 7);
        mem_ctrl.wb_sel = WB_CSR;
        mem_ctrl.csr_addr = CYCLE;
        mem_valid = 1;
        #1; check("MEM late CSR-use stalls", late_csr_use_hazard);
        mem_valid = 0;
        configure_alu_producer(wb_ctrl, 7);
        wb_ctrl.wb_sel = WB_CSR;
        wb_ctrl.csr_addr = CYCLE;
        wb_valid = 1;
        #1; check("WB late CSR-use no longer stalls", !late_csr_use_hazard);

        // CSR reads sample in ID, so CSR writes interlock through WB.
        clear_producers();
        id_ctrl = '0;
        id_ctrl.csr_read = 1;
        id_ctrl.csr_addr = MSTATUS;
        ex1_ctrl.csr_write = 1;
        ex1_ctrl.csr_addr = MSTATUS;
        ex1_valid = 1;
        #1; check("EX1 CSR write interlocks a read", csr_interlock_hazard);
        ex1_valid = 0;
        ex2_ctrl.csr_write = 1;
        ex2_ctrl.csr_addr = MSTATUS;
        ex2_valid = 1;
        #1; check("EX2 CSR write interlocks a read", csr_interlock_hazard);
        ex2_valid = 0;
        ex3_ctrl.csr_write = 1;
        ex3_ctrl.csr_addr = MSTATUS;
        ex3_valid = 1;
        #1; check("EX3 CSR write interlocks a read", csr_interlock_hazard);
        ex3_valid = 0;
        mem_ctrl.csr_write = 1;
        mem_ctrl.csr_addr = SSTATUS;
        mem_valid = 1;
        #1; check("MEM CSR alias write interlocks a read", csr_interlock_hazard);
        mem_valid = 0;
        wb_ctrl.csr_write = 1;
        wb_ctrl.csr_addr = MSTATUS;
        wb_valid = 1;
        #1; check("WB CSR write remains interlocked", csr_interlock_hazard);
        id_ctrl.csr_read = 0;
        #1; check("CSR writes without a read do not interlock", !csr_interlock_hazard);

        $display("tb_forwarding_hazard: all %0d checks passed", tests_run);
        $finish;
    end
endmodule
