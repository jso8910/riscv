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
    logic mtip;
    logic stip;
    logic [XLEN-1:0] time_i;
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
        .mtip_i(mtip),
        .stip_i(stip),
        .time_i(time_i),
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
        mtip = 1'b1;
        stip = 1'b0;
        time_i = '0;
        cycle_tick = 1'b0;
        retire_count = 1'b0;
        tests_run = 0;
        tests_failed = 0;
        clear_ctrl();

        rst_n = 1'b0;
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
                 MSTATUS_WRITE_MASK_VAL);

        write_csr(MEPC, 64'h0123_4567_0000_1003);
        read_csr("mepc clears its two low bits", MEPC, 64'h0123_4567_0000_1000);

        write_csr(MTVEC, 64'h0123_4567_0000_2002);
        read_csr("mtvec rejects reserved modes", MTVEC, 64'h0123_4567_0000_2000);

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
