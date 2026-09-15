`timescale 1ns/1ps

import riscv::*;

module tb_csrfile;
    logic clk;
    logic rst_n;
    ctrl_t ctrl;
    logic cycle_tick;
    logic retire_count;
    logic [XLEN-1:0] csr_data;
    logic [11:0] csr_read_addr;
    logic [11:0] csr_late_read_addr;
    trap_t trap;
    logic trap_take;
    logic mtip;
    logic stip;
    logic [XLEN-1:0] time_i;
    logic [XLEN-1:0] csr_val;
    logic [XLEN-1:0] csr_late_val;
    logic [XLEN-1:0] mepc;
    logic [XLEN-1:0] mtvec;
    logic [XLEN-1:0] mstatus;
    logic csr_illegal;
    machine_privilege_t privilege;
    logic csr_flush;
    int tests_run;
    int tests_failed;

    csrfile dut (
        .clk(clk),
        .rst_n(rst_n),
        .commit_i(1'b1),
        .trap_take_i(trap_take),
        .ctrl_i(ctrl),
        .cycle_tick_i(cycle_tick),
        .retire_count_i(retire_count),
        .csr_data_i(csr_data),
        .csr_read_addr_i(csr_read_addr),
        .csr_late_read_addr_i(csr_late_read_addr),
        .trap_i(trap),
        .mtip_i(mtip),
        .stip_i(stip),
        .time_i(time_i),
        .csr_val_o(csr_val),
        .csr_late_val_o(csr_late_val),
        .mepc_o(mepc),
        .mtvec_o(mtvec),
        .sepc_o(),
        .stvec_o(),
        .mstatus_o(mstatus),
        .stimecmp_o(),
        .pmp_cfg_o(),
        .pmp_addr_o(),
        .mip_o(),
        .mie_o(),
        .sip_o(),
        .sie_o(),
        .medeleg_o(),
        .mideleg_o(),
        .satp_o(),
        .csr_illegal_inst_o(csr_illegal),
        .machine_privilege_o(privilege),
        .csr_flush_o(csr_flush)
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
            csr_data = value;
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
            csr_read_addr = address;
            #1;
            check(name, !csr_illegal && csr_val === expected);
            clear_ctrl();
        end
    endtask

    task automatic enter_privilege(input machine_privilege_t destination);
        begin
            trap = '0;
            trap.is_trap = 1'b1;
            trap.dest_machine_privilege = destination;
            trap_take = 1'b1;
            @(posedge clk);
            #1;
            trap = '0;
            trap_take = 1'b0;
            check("trap changes privilege for policy test", privilege == destination);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b1;
        csr_data = '0;
        csr_read_addr = '0;
        csr_late_read_addr = '0;
        trap = '0;
        trap_take = 1'b0;
        mtip = 1'b1;
        stip = 1'b0;
        time_i = '0;
        cycle_tick = 1'b0;
        retire_count = 1'b0;
        tests_run = 0;
        tests_failed = 0;
        clear_ctrl();

        rst_n = 1'b0;
        @(posedge clk);
        #1;
        check("reset enters M-mode", privilege == M_MODE);
        read_csr("mstatus reset has MPP=M", MSTATUS, MSTATUS_VAL);
        read_csr("misa advertises I, S, and U", MISA, MISA_VAL);
        read_csr("mip reset has MTIP pending", MIP, 64'h0000_0000_0000_0080);

        rst_n = 1'b1;
        write_csr(MIE, '1);
        read_csr("mie implements standard interrupt enable bits", MIE, STANDARD_INTERRUPT_MASK);
        write_csr(MIP, '0);
        read_csr("mip ignores software writes", MIP, 64'h0000_0000_0000_0080);
        mtip = 1'b0;
        read_csr("MTIP deasserts when the timer source clears", MIP, '0);
        mtip = 1'b1;
        write_csr(MIP, (XLEN'(1) << S_EXTERNAL) | (XLEN'(1) << S_SOFTWARE));
        read_csr("mip retains writable supervisor software and external bits", MIP,
                 (XLEN'(1) << M_TIMER) | (XLEN'(1) << S_EXTERNAL) | (XLEN'(1) << S_SOFTWARE));

        write_csr(MIDELEG, '1);
        read_csr("mideleg implements supervisor interrupt delegation bits", MIDELEG,
                 SUPERVISOR_INTERRUPT_MASK);
        write_csr(SIE, '1);
        read_csr("sie writes delegated supervisor interrupt enables", SIE,
                 SUPERVISOR_INTERRUPT_MASK);
        write_csr(SIP, '0);
        read_csr("sip clears delegated SSIP but preserves external pending", SIP,
                 XLEN'(1) << S_EXTERNAL);
        write_csr(SIP, XLEN'(1) << S_SOFTWARE);
        read_csr("sip writes delegated SSIP", SIP,
                 (XLEN'(1) << S_EXTERNAL) | (XLEN'(1) << S_SOFTWARE));
        write_csr(MEDELEG, '1);
        read_csr("medeleg implements standard lower-privilege exceptions", MEDELEG,
                 MEDELEG_WRITABLE_MASK);

        write_csr(MSTATUS, '1);
        read_csr("mstatus retains supervisor status fields and MPRV", MSTATUS,
                 (MSTATUS_VAL & ~MSTATUS_WRITE_MASK_VAL) | MSTATUS_WRITE_MASK_VAL);

        // Only FIOM is implemented in each xenvcfg CSR.  senvcfg.FIOM
        // independently controls U-mode FENCE behavior.
        write_csr(SENVCFG, '1);
        read_csr("senvcfg implements FIOM", SENVCFG, XLEN'(1));
        write_csr(SENVCFG, '0);
        read_csr("senvcfg FIOM clears", SENVCFG, '0);
        write_csr(SSTATUS, '0);
        read_csr("sstatus exposes read-only UXL", SSTATUS,
                 XLEN'(2) << MSTATUS_UXL_LSB);

        // Exercise TVM, TW, and TSR independently.  These are intentionally
        // comb checks: a prohibited instruction must be identified before it
        // can commit any state change.
        write_csr(MSTATUS, MSTATUS_VAL | (XLEN'(1) << MSTATUS_TVM));
        enter_privilege(S_MODE);
        clear_ctrl();
        ctrl.csr_addr = SATP;
        ctrl.csr_read = 1'b1;
        #1;
        check("TVM rejects S-mode satp reads", csr_illegal);
        clear_ctrl();
        ctrl.tlb_invalidate = 1'b1;
        #1;
        check("TVM rejects S-mode SFENCE.VMA", csr_illegal);
        clear_ctrl();
        ctrl.wfi = 1'b1;
        #1;
        check("TVM alone does not reject WFI", !csr_illegal);
        enter_privilege(M_MODE);

        write_csr(MSTATUS, MSTATUS_VAL | (XLEN'(1) << MSTATUS_TW));
        check("TW-only setup clears TVM", !mstatus[MSTATUS_TVM]);
        check("TW-only setup sets TW", mstatus[MSTATUS_TW]);
        enter_privilege(S_MODE);
        clear_ctrl();
        ctrl.wfi = 1'b1;
        #1;
        check("TW rejects S-mode WFI", csr_illegal);
        clear_ctrl();
        ctrl.csr_addr = SATP;
        ctrl.csr_read = 1'b1;
        #1;
        check("TW alone permits satp access", !csr_illegal);
        enter_privilege(M_MODE);

        write_csr(MSTATUS, MSTATUS_VAL | (XLEN'(1) << MSTATUS_TSR));
        enter_privilege(S_MODE);
        clear_ctrl();
        ctrl.sret = 1'b1;
        #1;
        check("TSR rejects S-mode SRET", csr_illegal);
        clear_ctrl();
        ctrl.wfi = 1'b1;
        #1;
        check("TSR alone permits WFI", !csr_illegal);
        enter_privilege(M_MODE);

        write_csr(MEPC, 64'h0123_4567_0000_1003);
        read_csr("mepc clears its two low bits", MEPC, 64'h0123_4567_0000_1000);

        write_csr(MTVEC, 64'h0123_4567_0000_2002);
        read_csr("mtvec rejects reserved modes", MTVEC, 64'h0123_4567_0000_2000);

        // Only PMP_ENTRY_COUNT entries have storage.  Higher-numbered PMP
        // CSR slots are legal read-zero/write-ignore registers.
        write_csr(PMPADDR0 + 12'(PMP_ENTRY_COUNT), 64'h0123_4567_89ab_cdef);
        read_csr("unimplemented pmpaddr reads as zero", PMPADDR0 + 12'(PMP_ENTRY_COUNT), '0);
        write_csr(PMPCFG0 + 12'(2 * ((PMP_ENTRY_COUNT + 7) / 8)), '1);
        read_csr("unimplemented pmpcfg reads as zero",
                 PMPCFG0 + 12'(2 * ((PMP_ENTRY_COUNT + 7) / 8)), '0);

        write_csr(MCYCLE, 64'h0123_4567_89ab_cdef);
        read_csr("mcycle is writable", MCYCLE, 64'h0123_4567_89ab_cdef);

        cycle_tick = 1'b1;
        retire_count = 1'b1;
        @(posedge clk);
        #1;
        cycle_tick = 1'b0;
        retire_count = 1'b0;
        read_csr("mcycle increments on cycle_tick", MCYCLE, 64'h0123_4567_89ab_cdf0);
        read_csr("minstret increments on retire", MINSTRET, 64'h0000_0000_0000_0001);
        csr_late_read_addr = MCYCLE; #1;
        check("late mcycle read samples the counter", csr_late_val == 64'h0123_4567_89ab_cdf0);
        csr_late_read_addr = CYCLE; #1;
        check("late cycle read aliases mcycle", csr_late_val == 64'h0123_4567_89ab_cdf0);
        csr_late_read_addr = MINSTRET; #1;
        check("late minstret read samples the counter", csr_late_val == 64'h0000_0000_0000_0001);
        csr_late_read_addr = INSTRET; #1;
        check("late instret read aliases minstret", csr_late_val == 64'h0000_0000_0000_0001);
        time_i = 64'h0123_4567_89ab_cdef;
        csr_late_read_addr = TIME; #1;
        check("late time read samples time_i", csr_late_val == time_i);

        write_csr(MCOUNTINHIBIT, '1);
        read_csr("mcountinhibit exposes only CY and IR", MCOUNTINHIBIT, 64'h0000_0000_0000_0005);
        cycle_tick = 1'b1;
        retire_count = 1'b1;
        @(posedge clk);
        #1;
        cycle_tick = 1'b0;
        retire_count = 1'b0;
        read_csr("CY inhibit stops mcycle", MCYCLE, 64'h0123_4567_89ab_cdf0);
        read_csr("IR inhibit stops minstret", MINSTRET, 64'h0000_0000_0000_0001);

        write_csr(PMPADDR0, 64'h0000_0000_0000_0100);
        write_csr(PMPCFG0, 64'h0000_0000_0000_0088);
        write_csr(PMPADDR0, 64'h0000_0000_0000_0200);
        read_csr("locked PMP entry blocks pmpaddr writes", PMPADDR0, 64'h0000_0000_0000_0100);

        write_csr(PMPADDR0 + 12'd2, 64'h0000_0000_0000_0200);
        write_csr(PMPCFG0, 64'h0000_0000_8800_0088);
        write_csr(PMPADDR0 + 12'd2, 64'h0000_0000_0000_0300);
        read_csr("locked TOR entry locks the preceding pmpaddr", PMPADDR0 + 12'd2, 64'h0000_0000_0000_0200);

        write_csr(PMPADDR0 + 12'd4, '1);
        read_csr("pmpaddr exposes only implemented physical address bits", PMPADDR0 + 12'd4, 64'h003f_ffff_ffff_ffff);

        trap = '0;
        trap.is_trap = 1'b1;
        trap.pc = 32'h0000_0080;
        trap.exception_cause = BREAKPOINT;
        trap.dest_machine_privilege = M_MODE;
        trap_take = 1'b1;
        @(posedge clk);
        #1;
        trap = '0;
        trap_take = 1'b0;
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
