`timescale 1ns/1ps
import riscv::*;

module tb_control_helpers;
    logic [XLEN-1:0] fetch_pc, pred_pc, rs1, rs2, trap_pc;
    ctrl_t ctrl;
    sfence_sel_t sfence_sel;
    trap_t trap;
    logic trap_commit, trap_redirect;
    int tests_run, tests_failed;

    pc_prediction prediction (.if_fetch_pc_i(fetch_pc), .if_pred_pc_o(pred_pc));
    sfence_selector selector (.ctrl_i(ctrl), .rs1_data_i(rs1), .rs2_data_i(rs2), .sfence_sel_o(sfence_sel));
    trap_pc trap_target (.commit_i(trap_commit), .trap_i(trap), .mtvec_i(64'h100), .stvec_i(64'h201),
                         .next_pc_o(trap_pc), .trap_redirect_o(trap_redirect));

    task automatic check(input string name, input logic condition);
        begin #1; tests_run++; if (!condition) begin tests_failed++; $fatal(1, "%s", name); end end
    endtask

    initial begin
        tests_run = 0; tests_failed = 0; fetch_pc = 64'h80; ctrl = '0; rs1 = '0; rs2 = '0;
        trap = '0; trap_commit = 0;
        #1; check("sequential predictor adds four", pred_pc == 64'h84);
        ctrl.tlb_invalidate = 1; ctrl.rs1_addr = X0; ctrl.rs2_addr = X0;
        #1; check("SFENCE x0,x0 is a global selector", sfence_sel.valid && sfence_sel.vaddr_all && sfence_sel.asid_all);
        ctrl.rs1_addr = 1; ctrl.rs2_addr = 2; rs1 = 64'hffff_ffff_8123_4000; rs2 = 64'h1234 << SATP_ASID_LSB;
        #1; check("selective SFENCE retains VPN and ASID", sfence_sel.vaddr_canonical && sfence_sel.vpn == rs1[38:12]
              && sfence_sel.asid == 16'h1234);
        rs1 = 64'h0000_0080_0000_0000;
        #1; check("noncanonical selective SFENCE is marked invalid", !sfence_sel.vaddr_canonical);
        trap.is_trap = 1; trap.dest_machine_privilege = M_MODE; trap_commit = 1;
        #1; check("direct machine trap redirects to aligned mtvec", trap_redirect && trap_pc == 64'h100);
        trap.dest_machine_privilege = S_MODE; trap.is_interrupt = 1; trap.interrupt_cause = S_TIMER;
        #1; check("vectored supervisor interrupt uses stvec offset", trap_pc == 64'h214);
        trap_commit = 0;
        #1; check("unaccepted trap does not redirect", !trap_redirect);
        $display("tb_control_helpers: all %0d checks passed", tests_run);
        $finish;
    end
endmodule
