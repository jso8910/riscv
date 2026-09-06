`timescale 1ns/1ps

import riscv::*;

module tb_csrfile;
    logic clk;
    logic rst_n;
    ctrl_t ctrl;
    logic cycle_tick;
    logic retire_count;
    logic [XLEN-1:0] rs1;
    trap_t trap;
    logic [XLEN-1:0] csr_val;
    logic [XLEN-1:0] mepc;
    logic [XLEN-1:0] mtvec;
    logic csr_illegal;
    machine_privilege_t privilege;
    int tests_run;
    int tests_failed;

    csrfile dut (
        .clk(clk),
        .rst_n(rst_n),
        .ctrl_i(ctrl),
        .cycle_tick_i(cycle_tick),
        .retire_count_i(retire_count),
        .rs1_i(rs1),
        .trap_i(trap),
        .csr_val_o(csr_val),
        .mepc_o(mepc),
        .mtvec_o(mtvec),
        .csr_illegal_inst_o(csr_illegal),
        .machine_privilege_o(privilege)
    );

    always #5 clk = ~clk;

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

    task automatic clear_ctrl;
        begin
            ctrl = '0;
            ctrl.csr_wb_sel = WB_NORMAL;
        end
    endtask

    task automatic write_csr(
        input logic [11:0] address,
        input logic [XLEN-1:0] value
    );
        begin
            clear_ctrl();
            ctrl.csr_addr = address;
            rs1 = value;
            ctrl.csr_write = 1'b1;
            @(posedge clk);
            #1;
            clear_ctrl();
        end
    endtask

    task automatic read_csr(
        input string name,
        input logic [11:0] address,
        input logic [XLEN-1:0] expected
    );
        begin
            clear_ctrl();
            ctrl.csr_addr = address;
            ctrl.csr_read = 1'b1;
            #1;
            check(name, !csr_illegal && csr_val === expected);
            clear_ctrl();
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b1;
        rs1 = '0;
        trap = '0;
        cycle_tick = 1'b0;
        retire_count = 1'b0;
        tests_run = 0;
        tests_failed = 0;
        clear_ctrl();

        rst_n = 1'b0;
        #1;
        check("reset enters M-mode", privilege == M_MODE);
        read_csr("mstatus reset has MPP=M", MSTATUS, MSTATUS_VAL);

        rst_n = 1'b1;
        write_csr(MEPC, 32'h0000_1003);
        read_csr("mepc clears its two low bits", MEPC, 32'h0000_1000);

        write_csr(MTVEC, 32'h0000_2002);
        read_csr("mtvec rejects reserved modes", MTVEC, 32'h0000_2000);

        write_csr(MCYCLE, 32'h89ab_cdef);
        write_csr(MCYCLEH, 32'h0123_4567);
        read_csr("mcycle low half is writable", MCYCLE, 32'h89ab_cdef);
        read_csr("mcycle high half is writable", MCYCLEH, 32'h0123_4567);

        cycle_tick = 1'b1;
        retire_count = 1'b1;
        @(posedge clk);
        #1;
        cycle_tick = 1'b0;
        retire_count = 1'b0;
        read_csr("mcycle increments on cycle_tick", MCYCLE, 32'h89ab_cdf0);
        read_csr("minstret increments on retire", MINSTRET, 32'h0000_0001);

        write_csr(MCOUNTINHIBIT, 32'hffff_ffff);
        read_csr("mcountinhibit exposes only CY and IR", MCOUNTINHIBIT, 32'h0000_0005);
        cycle_tick = 1'b1;
        retire_count = 1'b1;
        @(posedge clk);
        #1;
        cycle_tick = 1'b0;
        retire_count = 1'b0;
        read_csr("CY inhibit stops mcycle", MCYCLE, 32'h89ab_cdf0);
        read_csr("IR inhibit stops minstret", MINSTRET, 32'h0000_0001);

        write_csr(PMPADDR0, 32'h0000_0100);
        write_csr(PMPCFG0, 32'h0000_0088);
        write_csr(PMPADDR0, 32'h0000_0200);
        read_csr("locked PMP entry blocks pmpaddr writes", PMPADDR0, 32'h0000_0100);

        write_csr(PMPADDR0 + 12'd2, 32'h0000_0200);
        write_csr(PMPCFG0, 32'h8800_0088);
        write_csr(PMPADDR0 + 12'd2, 32'h0000_0300);
        read_csr("locked TOR entry locks the preceding pmpaddr", PMPADDR0 + 12'd2, 32'h0000_0200);

        trap = '0;
        trap.is_trap = 1'b1;
        trap.pc = 32'h0000_0080;
        trap.exception_cause = BREAKPOINT;
        @(posedge clk);
        #1;
        trap = '0;
        check("trap entry writes mepc", mepc == 32'h0000_0080);
        read_csr("trap entry writes mcause", MCAUSE, 32'h0000_0003);

        clear_ctrl();
        ctrl.csr_addr = 12'h7ff;
        #1;
        ctrl.csr_read = 1'b1;
        #1;
        check("nonexistent CSR access is illegal", csr_illegal);

        if (tests_failed == 0) begin
            $display("tb_csrfile: all %0d checks passed", tests_run);
            $finish;
        end else begin
            $fatal(1, "tb_csrfile: %0d of %0d checks failed", tests_failed, tests_run);
        end
    end
endmodule : tb_csrfile
