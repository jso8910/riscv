`timescale 1ns/1ps

import riscv::*;

module tb_pma_checker;
    logic [7:0] pmp_cfg [0:PMP_ENTRY_COUNT-1];
    logic [XLEN-1:0] pmp_addr [0:PMP_ENTRY_COUNT-1];
    pmp_decoded_entry_t pmp_decoded [0:PMP_ENTRY_COUNT-1];
    mem_req_t [MEM_READ_PORTS-1:0] req;
    mem_fault_t [MEM_READ_PORTS-1:0] fault;
    logic [MEM_READ_PORTS-1:0][XLEN-1:0] fault_addr;
    int tests_run, tests_failed;

    physical_memory_checker dut (
        .pmp_decoded_i(pmp_decoded), .mem_req_i(req),
        .fault_o(fault), .fault_addr_o(fault_addr)
    );

    // The core receives these descriptors from csrfile registers.  Decode
    // combinationally here so the checker test can set PMP CSRs directly.
    always_comb begin
        for (int i = 0; i < PMP_ENTRY_COUNT; i++) begin
            if (i == 0)
                pmp_decoded[i] = decode_pmp_entry(pmp_cfg[i], pmp_addr[i], '0);
            else
                pmp_decoded[i] = decode_pmp_entry(pmp_cfg[i], pmp_addr[i], pmp_addr[i-1]);
        end
    end

    function automatic logic [7:0] pmpcfg(
        input pmp_addr_matching_t mode, input logic r, input logic w, input logic x
    );
        logic [7:0] value;
        begin
            value = '0;
            value[PMPCFG_A_MSB:PMPCFG_A_LSB] = mode;
            value[PMPCFG_R_IDX] = r;
            value[PMPCFG_W_IDX] = w;
            value[PMPCFG_X_IDX] = x;
            return value;
        end
    endfunction

    task automatic check(input string name, input logic condition);
        begin
            tests_run++;
            if (!condition) begin
                tests_failed++;
                $fatal(1, "%s", name);
            end
        end
    endtask

    task automatic clear_inputs;
        begin
            req = '0;
            for (int i = 0; i < PMP_ENTRY_COUNT; i++) begin
                pmp_cfg[i] = '0;
                pmp_addr[i] = '0;
            end
        end
    endtask

    task automatic make_request(
        input int port, input mem_op_t op, input mem_op_t original,
        input machine_privilege_t privilege, input mem_size_t size,
        input logic [XLEN-1:0] physical_address, input logic [XLEN-1:0] virtual_address
    );
        begin
            req[port] = '0;
            req[port].valid = 1'b1;
            req[port].op = op;
            req[port].op_original = original;
            req[port].effective_privilege = privilege;
            req[port].size = size;
            req[port].address = physical_address;
            req[port].virtual_address = virtual_address;
        end
    endtask

    initial begin
        tests_run = 0;
        tests_failed = 0;

        clear_inputs();
        make_request(0, MFETCH, MFETCH, M_MODE, MEM_WORD, MEM_START_ADDRESS, 64'h4000);
        #1;
        check("main-memory instruction fetch is permitted", fault[0] == FAULT_NONE);

        clear_inputs();
        make_request(0, MREAD, MREAD, M_MODE, MEM_DOUBLE, MEM_END_ADDRESS - 3, 64'h4008);
        #1;
        check("access spanning the PMA boundary faults", fault[0] == PMA_READ);
        check("fault address is the request virtual address", fault_addr[0] == 64'h4008);

        clear_inputs();
        // Permit PMP access through this otherwise invalid PMA address so the
        // test isolates the PMA result and its original-operation attribution.
        pmp_cfg[0] = pmpcfg(PMP_TOR, 1'b1, 1'b1, 1'b1);
        pmp_addr[0] = (XLEN'(MEM_END_ADDRESS) + 64'd16) >> 2;
        make_request(0, MREAD, MFETCH, S_MODE, MEM_DOUBLE,
                     MEM_END_ADDRESS + 1, 64'hffff_ffff_8000_1000);
        #1;
        check("PTW PMA denial retains original fetch attribution", fault[0] == PMA_FETCH);
        check("PTW PMA denial reports original virtual address",
              fault_addr[0] == 64'hffff_ffff_8000_1000);

        clear_inputs();
        pmp_cfg[0] = pmpcfg(PMP_NAPOT, 1'b1, 1'b0, 1'b0);
        pmp_addr[0] = 64'h1ff; // 4 KiB NAPOT range at physical address zero
        make_request(0, MWRITE, MWRITE, S_MODE, MEM_WORD, 64'h100, 64'h5000);
        make_request(1, MREAD, MREAD, S_MODE, MEM_WORD, 64'h100, 64'h6000);
        #1;
        check("PMP denies an S-mode write without W permission", fault[0] == PMP_WRITE);
        check("PMP permits a concurrently issued read with R permission", fault[1] == FAULT_NONE);

        clear_inputs();
        pmp_cfg[0] = pmpcfg(PMP_NA4, 1'b1, 1'b1, 1'b0);
        pmp_addr[0] = 64'h100 >> 2;
        pmp_cfg[1] = pmpcfg(PMP_NAPOT, 1'b1, 1'b0, 1'b0);
        pmp_addr[1] = 64'h1ff;
        make_request(0, MWRITE, MWRITE, S_MODE, MEM_WORD, 64'h100, 64'h7000);
        #1;
        check("lowest-numbered overlapping PMP wins", fault[0] == FAULT_NONE);

        clear_inputs();
        pmp_cfg[0] = pmpcfg(PMP_NA4, 1'b1, 1'b1, 1'b0);
        pmp_addr[0] = 64'h100 >> 2;
        make_request(0, MREAD, MREAD, S_MODE, MEM_WORD, 64'h102, 64'h7004);
        #1;
        check("access partially outside selected PMP faults", fault[0] == PMP_READ);

        clear_inputs();
        pmp_cfg[0] = pmpcfg(PMP_NAPOT, 1'b1, 1'b0, 1'b0);
        pmp_addr[0] = 64'h1ff;
        make_request(0, MWRITE, MWRITE, M_MODE, MEM_WORD, 64'h100, 64'h7000);
        #1;
        check("unlocked PMP permissions are bypassed in M mode", fault[0] == FAULT_NONE);

        if (tests_failed == 0) begin
            $display("tb_pma_checker: all %0d checks passed", tests_run);
            $finish;
        end else
            $fatal(1, "tb_pma_checker: %0d of %0d checks failed", tests_failed, tests_run);
    end
endmodule : tb_pma_checker
