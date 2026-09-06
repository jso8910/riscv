`timescale 1ns/1ps

import riscv::*;

module tb_trap_controller;
    ctrl_t ctrl;
    logic csr_illegal;
    logic address_misaligned;
    logic hardware_fault;
    logic pma_fetch_fault;
    logic pma_write_fault;
    logic pma_read_fault;
    logic [XLEN-1:0] pma_faulting_addr;
    machine_privilege_t privilege;
    logic [XLEN-1:0] pc;
    trap_t trap;
    int tests_run;
    int tests_failed;

    trap_controller dut (
        .ctrl_i(ctrl),
        .hardware_fault_i(hardware_fault),
        .csr_illegal_inst_i(csr_illegal),
        .address_misaligned_i(address_misaligned),
        .pma_instruction_fetch_exception_i(pma_fetch_fault),
        .pma_write_exception_i(pma_write_fault),
        .pma_read_exception_i(pma_read_fault),
        .current_privilege_i(privilege),
        .pma_faulting_addr_i(pma_faulting_addr),
        .pc_i(pc),
        .trap_o(trap)
    );

    task automatic check(
        input string name,
        input logic expected_trap,
        input trap_exception_cause_t expected_cause
    );
        begin
            #1;
            tests_run++;
            if (trap.is_trap !== expected_trap ||
                (expected_trap && trap.exception_cause !== expected_cause)) begin
                tests_failed++;
                $fatal(1, "%s: expected trap=%0b cause=%0d, got trap=%0b cause=%0d",
                       name, expected_trap, expected_cause, trap.is_trap, trap.exception_cause);
            end
        end
    endtask

    task automatic check_tval(
        input string name,
        input logic [XLEN-1:0] expected_tval
    );
        begin
            #1;
            tests_run++;
            if (trap.tval !== expected_tval) begin
                tests_failed++;
                $fatal(1, "%s: expected mtval=0x%08x, got 0x%08x",
                       name, expected_tval, trap.tval);
            end
        end
    endtask

    task automatic clear_inputs;
        begin
            ctrl = '0;
            csr_illegal = 1'b0;
            address_misaligned = 1'b0;
            hardware_fault = 1'b0;
            pma_fetch_fault = 1'b0;
            pma_write_fault = 1'b0;
            pma_read_fault = 1'b0;
            pma_faulting_addr = 32'h0000_1234;
            privilege = M_MODE;
            pc = 32'h0000_0080;
        end
    endtask

    initial begin
        tests_run = 0;
        tests_failed = 0;

        clear_inputs();
        check("no event does not trap", 1'b0, INST_ADDR_MISALIGNED);

        clear_inputs();
        hardware_fault = 1'b1;
        check("hardware fault has highest priority", 1'b1, HARDWARE_ERROR);

        clear_inputs();
        csr_illegal = 1'b1;
        check("illegal CSR access traps as illegal instruction", 1'b1, ILLEGAL_INSTRUCTION);

        clear_inputs();
        ctrl.ecall = 1'b1;
        check("M-mode ECALL traps with the machine cause", 1'b1, ECALL_FROM_M_MODE);

        clear_inputs();
        ctrl.ebreak = 1'b1;
        check("EBREAK traps as breakpoint", 1'b1, BREAKPOINT);

        clear_inputs();
        address_misaligned = 1'b1;
        check("misaligned instruction target traps", 1'b1, INST_ADDR_MISALIGNED);

        clear_inputs();
        pma_fetch_fault = 1'b1;
        check("PMA fetch denial traps as instruction access fault", 1'b1, INST_ACCESS_FAULT);
        check_tval("instruction access fault forwards its PMA address", pma_faulting_addr);

        clear_inputs();
        pma_write_fault = 1'b1;
        check("PMA write denial traps as store access fault", 1'b1, STORE_ACCESS_FAULT);
        check_tval("store access fault forwards its PMA address", pma_faulting_addr);

        clear_inputs();
        pma_read_fault = 1'b1;
        check("PMA read denial traps as load access fault", 1'b1, LOAD_ACCESS_FAULT);
        check_tval("load access fault forwards its PMA address", pma_faulting_addr);

        if (tests_failed == 0) begin
            $display("tb_trap_controller: all %0d checks passed", tests_run);
            $finish;
        end else begin
            $fatal(1, "tb_trap_controller: %0d of %0d checks failed", tests_failed, tests_run);
        end
    end
endmodule : tb_trap_controller
