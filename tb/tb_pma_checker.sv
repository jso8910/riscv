`timescale 1ns/1ps

import riscv::*;

module tb_pma_checker;
    logic [XLEN-1:0] pc;
    ctrl_t ctrl;
    logic [XLEN-1:0] data_addr;
    machine_privilege_t current_privilege;
    logic [7:0] pmp_cfg [0:63];
    logic [XLEN-1:0] pmp_addr [0:63];
    logic pma_fetch_fault;
    logic pma_write_fault;
    logic pma_read_fault;
    logic hardware_fault;
    logic [XLEN-1:0] pma_faulting_addr;
    logic pmp_fetch_fault;
    logic pmp_write_fault;
    logic pmp_read_fault;
    logic [XLEN-1:0] pmp_faulting_addr;
    int tests_run;
    int tests_failed;

    physical_memory_checker dut (
        .current_privilege_i(current_privilege),
        .pmp_cfg_i(pmp_cfg),
        .pmp_addr_i(pmp_addr),
        .pc_i(pc),
        .ctrl_i(ctrl),
        .data_mem_addr_i(data_addr),
        .pma_instruction_fetch_exception_o(pma_fetch_fault),
        .pma_write_exception_o(pma_write_fault),
        .pma_read_exception_o(pma_read_fault),
        .hardware_fault_o(hardware_fault),
        .pma_faulting_addr_o(pma_faulting_addr),
        .pmp_instruction_fetch_exception_o(pmp_fetch_fault),
        .pmp_write_exception_o(pmp_write_fault),
        .pmp_read_exception_o(pmp_read_fault),
        .pmp_faulting_addr_o(pmp_faulting_addr)
    );

    function automatic logic [7:0] pmpcfg(
        input logic lock,
        input pmp_addr_matching_t address_mode,
        input logic executable,
        input logic writable,
        input logic readable
    );
        begin
            pmpcfg = '0;
            pmpcfg[PMPCFG_L_IDX] = lock;
            pmpcfg[PMPCFG_A_MSB : PMPCFG_A_LSB] = address_mode;
            pmpcfg[PMPCFG_X_IDX] = executable;
            pmpcfg[PMPCFG_W_IDX] = writable;
            pmpcfg[PMPCFG_R_IDX] = readable;
        end
    endfunction

    task automatic clear_pmp;
        begin
            for (int i = 0; i < PMP_ENTRY_COUNT; i++) begin
                pmp_cfg[i] = '0;
                pmp_addr[i] = '0;
            end
        end
    endtask

    task automatic check_fetch(
        input string name,
        input logic [XLEN-1:0] address,
        input logic expected_fault
    );
        begin
            ctrl = '0;
            pc = address;
            data_addr = '0;
            #1;
            tests_run++;
            if (pma_fetch_fault !== expected_fault) begin
                tests_failed++;
                $fatal(1, "%s: expected PMA fetch fault=%0b, got %0b", name, expected_fault, pma_fetch_fault);
            end
        end
    endtask

    task automatic check_data(
        input string name,
        input logic read,
        input logic write,
        input mem_size_t size,
        input logic [XLEN-1:0] address,
        input logic expected_read_fault,
        input logic expected_write_fault
    );
        begin
            ctrl = '0;
            ctrl.mem_read = read;
            ctrl.mem_write = write;
            ctrl.mem_size = size;
            pc = IMEM_START_ADDRESS;
            data_addr = address;
            #1;
            tests_run++;
            if (pma_read_fault !== expected_read_fault || pma_write_fault !== expected_write_fault) begin
                tests_failed++;
                $fatal(1, "%s: expected PMA read/write faults %0b/%0b, got %0b/%0b",
                       name, expected_read_fault, expected_write_fault, pma_read_fault, pma_write_fault);
            end
        end
    endtask

    task automatic check_idle;
        begin
            ctrl = '0;
            pc = IMEM_START_ADDRESS;
            data_addr = '0;
            #1;
            tests_run++;
            if (hardware_fault || pma_fetch_fault || pma_read_fault || pma_write_fault) begin
                tests_failed++;
                $fatal(1, "an instruction with no data access must not raise a PMA fault");
            end
        end
    endtask

    task automatic check_no_hardware_fault(
        input string name,
        input logic read,
        input logic write,
        input mem_size_t size,
        input logic [XLEN-1:0] address
    );
        begin
            ctrl = '0;
            ctrl.mem_read = read;
            ctrl.mem_write = write;
            ctrl.mem_size = size;
            pc = IMEM_START_ADDRESS;
            data_addr = address;
            #1;
            tests_run++;
            if (hardware_fault) begin
                tests_failed++;
                $fatal(1, "%s: valid access must not raise a hardware fault", name);
            end
        end
    endtask

    task automatic check_faulting_addr(
        input string name,
        input logic read,
        input logic write,
        input mem_size_t size,
        input logic [XLEN-1:0] fetch_address,
        input logic [XLEN-1:0] access_address,
        input logic expected_fetch_fault,
        input logic expected_read_fault,
        input logic expected_write_fault,
        input logic [XLEN-1:0] expected_faulting_addr
    );
        begin
            ctrl = '0;
            ctrl.mem_read = read;
            ctrl.mem_write = write;
            ctrl.mem_size = size;
            pc = fetch_address;
            data_addr = access_address;
            #1;
            tests_run++;
            if (pma_fetch_fault !== expected_fetch_fault
                || pma_read_fault !== expected_read_fault
                || pma_write_fault !== expected_write_fault
                || pma_faulting_addr !== expected_faulting_addr) begin
                tests_failed++;
                $fatal(1, "%s: expected faults F/R/W=%0b/%0b/%0b and addr=0x%08x, got %0b/%0b/%0b and 0x%08x",
                       name, expected_fetch_fault, expected_read_fault, expected_write_fault,
                       expected_faulting_addr, pma_fetch_fault, pma_read_fault, pma_write_fault, pma_faulting_addr);
            end
        end
    endtask

    task automatic check_pmp_data(
        input string name,
        input machine_privilege_t privilege,
        input logic read,
        input logic write,
        input mem_size_t size,
        input logic [XLEN-1:0] address,
        input logic expected_read_fault,
        input logic expected_write_fault
    );
        begin
            ctrl = '0;
            ctrl.mem_read = read;
            ctrl.mem_write = write;
            ctrl.mem_size = size;
            current_privilege = privilege;
            pc = IMEM_START_ADDRESS;
            data_addr = address;
            #1;
            tests_run++;
            if (pmp_read_fault !== expected_read_fault || pmp_write_fault !== expected_write_fault) begin
                tests_failed++;
                $fatal(1, "%s: expected PMP read/write faults %0b/%0b, got %0b/%0b",
                       name, expected_read_fault, expected_write_fault, pmp_read_fault, pmp_write_fault);
            end
        end
    endtask

    task automatic check_pmp_fetch(
        input string name,
        input machine_privilege_t privilege,
        input logic [XLEN-1:0] address,
        input logic expected_fault
    );
        begin
            ctrl = '0;
            current_privilege = privilege;
            pc = address;
            data_addr = '0;
            #1;
            tests_run++;
            if (pmp_fetch_fault !== expected_fault) begin
                tests_failed++;
                $fatal(1, "%s: expected PMP fetch fault=%0b, got %0b", name, expected_fault, pmp_fetch_fault);
            end
        end
    endtask

    task automatic check_pmp_faulting_addr(
        input string name,
        input logic read,
        input logic write,
        input mem_size_t size,
        input logic [XLEN-1:0] address,
        input logic [XLEN-1:0] expected_addr
    );
        begin
            ctrl = '0;
            ctrl.mem_read = read;
            ctrl.mem_write = write;
            ctrl.mem_size = size;
            current_privilege = M_MODE;
            pc = IMEM_START_ADDRESS;
            data_addr = address;
            #1;
            tests_run++;
            if (pmp_faulting_addr !== expected_addr) begin
                tests_failed++;
                $fatal(1, "%s: expected PMP fault address 0x%08x, got 0x%08x",
                       name, expected_addr, pmp_faulting_addr);
            end
        end
    endtask

    initial begin
        tests_run = 0;
        tests_failed = 0;
        current_privilege = M_MODE;
        clear_pmp();

        check_fetch("IMEM is executable", IMEM_START_ADDRESS, 1'b0);
        check_fetch("DMEM main memory is executable", DMEM_START_ADDRESS, 1'b0);
        check_fetch("unallocated memory is not executable", DMEM_END_ADDRESS + 1, 1'b1);
        check_fetch("fetch crossing the IMEM/DMEM boundary is allowed", IMEM_END_ADDRESS - 1, 1'b0);
        check_idle();
        check_no_hardware_fault("valid word load", 1'b1, 1'b0, MEM_WORD, DMEM_START_ADDRESS);
        check_no_hardware_fault("valid word store", 1'b0, 1'b1, MEM_WORD, DMEM_START_ADDRESS);

        check_data("DMEM word read is allowed", 1'b1, 1'b0, MEM_WORD,
                   DMEM_START_ADDRESS, 1'b0, 1'b0);
        check_data("DMEM word write is allowed", 1'b0, 1'b1, MEM_WORD,
                   DMEM_START_ADDRESS, 1'b0, 1'b0);
        check_data("IMEM read is allowed even though it is read-only", 1'b1, 1'b0, MEM_WORD,
                   IMEM_START_ADDRESS, 1'b0, 1'b0);
        check_data("IMEM write is denied", 1'b0, 1'b1, MEM_WORD,
                   IMEM_START_ADDRESS, 1'b0, 1'b1);
        check_data("unallocated read is denied", 1'b1, 1'b0, MEM_BYTE,
                   DMEM_END_ADDRESS + 1, 1'b1, 1'b0);
        check_data("unallocated write is denied", 1'b0, 1'b1, MEM_BYTE,
                   DMEM_END_ADDRESS + 1, 1'b0, 1'b1);
        check_data("word crossing out of DMEM is denied", 1'b1, 1'b0, MEM_WORD,
                   DMEM_END_ADDRESS - 1, 1'b1, 1'b0);

        check_faulting_addr("load selects the lowest failing byte", 1'b1, 1'b0, MEM_WORD,
                            IMEM_START_ADDRESS, DMEM_END_ADDRESS - 1,
                            1'b0, 1'b1, 1'b0, DMEM_END_ADDRESS + 1);
        check_faulting_addr("store selects the lowest failing byte", 1'b0, 1'b1, MEM_WORD,
                            IMEM_START_ADDRESS, IMEM_START_ADDRESS,
                            1'b0, 1'b0, 1'b1, IMEM_START_ADDRESS);
        check_faulting_addr("fetch selects the first failing instruction byte", 1'b0, 1'b0, MEM_NONE,
                            DMEM_END_ADDRESS - 1, '0,
                            1'b1, 1'b0, 1'b0, DMEM_END_ADDRESS + 1);
        check_faulting_addr("fetch fault address wins over a data fault", 1'b1, 1'b0, MEM_WORD,
                            DMEM_END_ADDRESS + 8, DMEM_END_ADDRESS - 1,
                            1'b1, 1'b1, 1'b0, DMEM_END_ADDRESS + 8);

        // PMP tests: all PMP exceptions are checked independently of PMA exceptions.
        clear_pmp();
        check_pmp_data("M mode allows an unmatched read", M_MODE, 1'b1, 1'b0, MEM_WORD,
                       DMEM_START_ADDRESS, 1'b0, 1'b0);
        check_pmp_fetch("M mode allows an unmatched fetch", M_MODE, IMEM_START_ADDRESS, 1'b0);

        clear_pmp();
        pmp_cfg[0] = pmpcfg(1'b0, PMP_NA4, 1'b0, 1'b0, 1'b0);
        pmp_addr[0] = (DMEM_START_ADDRESS + 32'h100) >> 2;
        check_pmp_data("unlocked M PMP bypasses write permission", M_MODE, 1'b0, 1'b1, MEM_BYTE,
                       DMEM_START_ADDRESS + 32'h100, 1'b0, 1'b0);

        clear_pmp();
        pmp_cfg[0] = pmpcfg(1'b1, PMP_NA4, 1'b0, 1'b0, 1'b1);
        pmp_addr[0] = (DMEM_START_ADDRESS + 32'h100) >> 2;
        check_pmp_data("locked M PMP allows read", M_MODE, 1'b1, 1'b0, MEM_BYTE,
                       DMEM_START_ADDRESS + 32'h100, 1'b0, 1'b0);
        check_pmp_data("locked M PMP denies write", M_MODE, 1'b0, 1'b1, MEM_BYTE,
                       DMEM_START_ADDRESS + 32'h100, 1'b0, 1'b1);

        clear_pmp();
        pmp_cfg[0] = pmpcfg(1'b1, PMP_TOR, 1'b0, 1'b1, 1'b1);
        pmp_addr[0] = (IMEM_END_ADDRESS + 1) >> 2;
        check_pmp_fetch("locked M PMP denies execute without X", M_MODE, IMEM_START_ADDRESS, 1'b1);

        clear_pmp();
        check_pmp_data("U mode denies unmatched access when PMP exists", U_MODE, 1'b1, 1'b0, MEM_BYTE,
                       DMEM_START_ADDRESS, 1'b1, 1'b0);
        check_pmp_fetch("U mode denies unmatched fetch when all entries are OFF", U_MODE,
                        IMEM_START_ADDRESS, 1'b1);

        clear_pmp();
        pmp_cfg[0] = pmpcfg(1'b0, PMP_TOR, 1'b1, 1'b0, 1'b0);
        pmp_addr[0] = (IMEM_END_ADDRESS + 1) >> 2;
        check_pmp_fetch("execute-only PMP region permits U-mode fetch", U_MODE, IMEM_START_ADDRESS, 1'b0);
        check_pmp_data("execute-only PMP region denies U-mode read", U_MODE, 1'b1, 1'b0, MEM_BYTE,
                       IMEM_START_ADDRESS, 1'b1, 1'b0);

        clear_pmp();
        pmp_addr[0] = (DMEM_START_ADDRESS + 32'h100) >> 2;
        pmp_cfg[1] = pmpcfg(1'b0, PMP_TOR, 1'b0, 1'b1, 1'b1);
        pmp_addr[1] = (DMEM_START_ADDRESS + 32'h110) >> 2;
        check_pmp_data("TOR uses the preceding PMP address as its lower bound", U_MODE,
                       1'b1, 1'b0, MEM_BYTE, DMEM_START_ADDRESS + 32'h104, 1'b0, 1'b0);
        check_pmp_data("TOR does not match below its preceding PMP address", U_MODE,
                       1'b1, 1'b0, MEM_BYTE, DMEM_START_ADDRESS + 32'h0fc, 1'b1, 1'b0);

        clear_pmp();
        pmp_cfg[0] = pmpcfg(1'b1, PMP_NAPOT, 1'b0, 1'b0, 1'b1);
        pmp_addr[0] = ((DMEM_START_ADDRESS + 32'h200) >> 2) | 32'h3;
        check_pmp_data("NAPOT read is allowed", M_MODE, 1'b1, 1'b0, MEM_BYTE,
                       DMEM_START_ADDRESS + 32'h210, 1'b0, 1'b0);
        check_pmp_data("NAPOT write is denied", M_MODE, 1'b0, 1'b1, MEM_BYTE,
                       DMEM_START_ADDRESS + 32'h210, 1'b0, 1'b1);

        clear_pmp();
        pmp_cfg[0] = pmpcfg(1'b0, PMP_NA4, 1'b0, 1'b0, 1'b1);
        pmp_addr[0] = (DMEM_START_ADDRESS + 32'h008) >> 2;
        pmp_cfg[1] = pmpcfg(1'b1, PMP_NAPOT, 1'b0, 1'b0, 1'b1);
        pmp_addr[1] = (DMEM_START_ADDRESS >> 2) | 32'h3;
        check_pmp_data("lowest PMP entry wins and partial coverage faults", M_MODE, 1'b1, 1'b0, MEM_WORD,
                       DMEM_START_ADDRESS + 32'h006, 1'b1, 1'b0);

        clear_pmp();
        pmp_cfg[0] = pmpcfg(1'b1, PMP_NA4, 1'b0, 1'b0, 1'b0);
        pmp_addr[0] = (DMEM_START_ADDRESS + 32'h100) >> 2;
        pmp_cfg[1] = pmpcfg(1'b1, PMP_NAPOT, 1'b0, 1'b0, 1'b1);
        pmp_addr[1] = ((DMEM_START_ADDRESS + 32'h100) >> 2) | 32'h3;
        check_pmp_data("lowest matching PMP permission wins", M_MODE, 1'b1, 1'b0, MEM_BYTE,
                       DMEM_START_ADDRESS + 32'h100, 1'b1, 1'b0);

        clear_pmp();
        pmp_cfg[0] = pmpcfg(1'b0, PMP_TOR, 1'b1, 1'b1, 1'b1);
        pmp_addr[0] = 32'h4000_0000;
        check_pmp_data("TOR top at 2^32 covers 32-bit data address", U_MODE, 1'b1, 1'b0, MEM_WORD,
                       DMEM_START_ADDRESS, 1'b0, 1'b0);
        check_pmp_fetch("TOR top at 2^32 covers 32-bit fetch address", U_MODE, IMEM_START_ADDRESS, 1'b0);

        clear_pmp();
        pmp_cfg[0] = pmpcfg(1'b1, PMP_TOR, 1'b1, 1'b1, 1'b1);
        pmp_addr[0] = (IMEM_END_ADDRESS + 1) >> 2;
        pmp_cfg[1] = pmpcfg(1'b1, PMP_NA4, 1'b0, 1'b0, 1'b0);
        pmp_addr[1] = (DMEM_START_ADDRESS + 32'h100) >> 2;
        check_pmp_faulting_addr("PMP data fault reports the original access address", 1'b0, 1'b1, MEM_BYTE,
                                DMEM_START_ADDRESS + 32'h100, DMEM_START_ADDRESS + 32'h100);

        if (tests_failed == 0) begin
            $display("tb_pma_checker: all %0d checks passed", tests_run);
            $finish;
        end else begin
            $fatal(1, "tb_pma_checker: %0d of %0d checks failed", tests_failed, tests_run);
        end
    end
endmodule : tb_pma_checker
