`timescale 1ns/1ps

import riscv::*;

module tb_trap_controller;
    ctrl_t ctrl;
    logic hardware_fault, csr_illegal, address_misaligned;
    mem_fault_t [MEM_READ_PORTS-1:0] mem_fault;
    logic [MEM_READ_PORTS-1:0][XLEN-1:0] mem_fault_addr;
    logic load_page_fault, store_page_fault, fetch_page_fault;
    logic [XLEN-1:0] page_fault_addr;
    logic [XLEN-1:0] mip, mie, sip, sie, mstatus, mideleg, medeleg;
    machine_privilege_t privilege;
    logic [XLEN-1:0] pc;
    trap_t trap;
    int tests_run, tests_failed;

    trap_controller dut (
        .ctrl_i(ctrl), .hardware_fault_i(hardware_fault),
        .csr_illegal_inst_i(csr_illegal), .address_misaligned_i(address_misaligned),
        .mem_fault_i(mem_fault), .mem_fault_addr_i(mem_fault_addr),
        .load_page_fault_i(load_page_fault), .store_page_fault_i(store_page_fault),
        .fetch_page_fault_i(fetch_page_fault), .page_fault_addr_i(page_fault_addr),
        .mip_i(mip), .mie_i(mie), .sip_i(sip), .sie_i(sie), .mstatus_i(mstatus),
        .mideleg_i(mideleg), .medeleg_i(medeleg), .current_privilege_i(privilege),
        .pc_i(pc), .trap_o(trap)
    );

    task automatic check(
        input string name, input logic expected_trap,
        input trap_exception_cause_t expected_cause, input logic [XLEN-1:0] expected_tval
    );
        begin
            #1;
            tests_run++;
            if (trap.is_trap !== expected_trap ||
                (expected_trap && (!trap.is_interrupt && trap.exception_cause !== expected_cause ||
                                   trap.tval !== expected_tval))) begin
                tests_failed++;
                $fatal(1, "%s: trap=%0b cause=%0d tval=%h", name, trap.is_trap,
                       trap.exception_cause, trap.tval);
            end
        end
    endtask

    task automatic clear_inputs;
        begin
            ctrl = '0;
            hardware_fault = 0;
            csr_illegal = 0;
            address_misaligned = 0;
            mem_fault = '0;
            mem_fault_addr = '0;
            load_page_fault = 0;
            store_page_fault = 0;
            fetch_page_fault = 0;
            page_fault_addr = '0;
            mip = '0; mie = '0; sip = '0; sie = '0; mstatus = '0;
            mideleg = '0; medeleg = '0;
            privilege = M_MODE;
            pc = 64'h80;
        end
    endtask

    initial begin
        tests_run = 0;
        tests_failed = 0;
        clear_inputs();
        check("no event has no trap", 0, INST_ADDR_MISALIGNED, '0);

        clear_inputs();
        fetch_page_fault = 1;
        page_fault_addr = 64'hffff_ffff_8000_0100;
        check("fetch page fault has instruction cause and virtual tval", 1,
              INSTRUCTION_PAGE_FAULT, page_fault_addr);

        clear_inputs();
        store_page_fault = 1;
        page_fault_addr = 64'h2004;
        check("store page fault has store cause", 1, STORE_PAGE_FAULT, page_fault_addr);

        clear_inputs();
        mem_fault[0] = PMP_READ;
        mem_fault_addr[0] = 64'h3008;
        check("PMP read fault becomes a load access fault", 1, LOAD_ACCESS_FAULT, 64'h3008);

        clear_inputs();
        mem_fault[0] = PMA_WRITE;
        mem_fault_addr[0] = 64'h4000;
        fetch_page_fault = 1;
        page_fault_addr = 64'h5000;
        check("fetch fault priority beats data access fault", 1,
              INSTRUCTION_PAGE_FAULT, 64'h5000);

        clear_inputs();
        ctrl.ecall = 1;
        privilege = S_MODE;
        check("S-mode ECALL has its distinct cause", 1, ECALL_FROM_S_MODE, '0);

        if (tests_failed == 0) begin
            $display("tb_trap_controller: all %0d checks passed", tests_run);
            $finish;
        end else
            $fatal(1, "tb_trap_controller: %0d of %0d checks failed", tests_failed, tests_run);
    end
endmodule : tb_trap_controller
