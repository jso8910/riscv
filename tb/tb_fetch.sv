`timescale 1ns/1ps

import riscv::*;

// Unit tests for the one-entry instruction buffer. fetch_pc is the address
// of the outstanding/predicted fetch; inst_pc belongs to the buffered slot.
module tb_fetch;
    logic clk;
    logic rst_n;
    logic [XLEN-1:0] next_pc;
    mem_res_t fetch_mem_res;
    mem_req_t fetch_mem_req;
    logic fetch_page_fault;
    logic [XLEN-1:0] fetch_page_fault_addr;
    mem_fault_t fetch_mem_fault;
    logic [XLEN-1:0] fetch_mem_fault_addr;
    logic commit;

    logic [XLEN-1:0] fetch_pc;
    logic [XLEN-1:0] inst_pc;
    logic [IALIGN-1:0] inst;
    logic inst_valid;
    mem_fault_t inst_mem_fault;
    logic [XLEN-1:0] inst_mem_fault_addr;
    logic inst_page_fault;
    logic [XLEN-1:0] inst_page_fault_addr;

    int tests_run;
    int tests_failed;

    fetch dut (
        .clk(clk),
        .rst_n(rst_n),
        .next_pc_i(next_pc),
        .fetch_mem_res_i(fetch_mem_res),
        .fetch_mem_req_i(fetch_mem_req),
        .fetch_page_fault_i(fetch_page_fault),
        .fetch_page_fault_addr_i(fetch_page_fault_addr),
        .fetch_mem_fault_i(fetch_mem_fault),
        .fetch_mem_fault_addr_i(fetch_mem_fault_addr),
        .commit_i(commit),
        .fetch_pc_o(fetch_pc),
        .inst_pc_o(inst_pc),
        .inst_o(inst),
        .inst_valid_o(inst_valid),
        .inst_mem_fault_q(inst_mem_fault),
        .inst_mem_fault_addr_q(inst_mem_fault_addr),
        .inst_page_fault_q(inst_page_fault),
        .inst_page_fault_addr_q(inst_page_fault_addr)
    );

    always #5 clk = ~clk;

    task automatic check(input string name, input logic condition);
        begin
            tests_run++;
            if (!condition) begin
                tests_failed++;
                $fatal(1, "%s", name);
            end
        end
    endtask

    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic drive_fetch_response(input logic [IALIGN-1:0] instruction);
        begin
            fetch_mem_req = '0;
            fetch_mem_req.valid = 1'b1;
            fetch_mem_req.op = MFETCH;
            fetch_mem_res = '0;
            fetch_mem_res.valid = 1'b1;
            fetch_mem_res.data[31:0] = instruction;
            fetch_page_fault = 1'b0;
            fetch_mem_fault = FAULT_NONE;
        end
    endtask

    task automatic drive_no_fetch_outcome;
        begin
            fetch_mem_req = '0;
            fetch_mem_req.valid = 1'b1;
            fetch_mem_req.op = MFETCH;
            fetch_mem_res = '0;
            fetch_page_fault = 1'b0;
            fetch_mem_fault = FAULT_NONE;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        next_pc = RESET_PC + PC_INC;
        fetch_page_fault_addr = '0;
        fetch_mem_fault_addr = '0;
        commit = 1'b0;
        tests_run = 0;
        tests_failed = 0;
        drive_no_fetch_outcome();

        #1;
        check("reset starts fetching at RESET_PC", fetch_pc == RESET_PC);
        check("reset leaves the instruction slot empty", !inst_valid);
        check("reset clears buffered access fault", inst_mem_fault == FAULT_NONE);
        check("reset clears buffered page fault", !inst_page_fault);

        // Empty-slot fill must work at boot even though no instruction retires.
        drive_fetch_response(32'h1111_1111);
        rst_n = 1'b1;
        tick();
        check("boot response fills the empty slot", inst_valid);
        check("boot response has RESET_PC", inst_pc == RESET_PC);
        check("boot response preserves instruction data", inst == 32'h1111_1111);
        check("boot advances the predicted fetch PC", fetch_pc == RESET_PC + PC_INC);

        // A response cannot overwrite an unretired buffered instruction.
        drive_fetch_response(32'h2222_2222);
        commit = 1'b0;
        next_pc = RESET_PC + PC_INC;
        tick();
        check("unretired instruction remains valid", inst_valid);
        check("unretired instruction is not overwritten", inst == 32'h1111_1111);
        check("stall retains outstanding fetch address", fetch_pc == RESET_PC + PC_INC);

        // Retiring the current instruction permits an atomic replacement.
        commit = 1'b1;
        tick();
        check("retirement accepts replacement instruction", inst == 32'h2222_2222);
        check("replacement receives outstanding fetch PC", inst_pc == RESET_PC + PC_INC);
        check("replacement advances fetch PC", fetch_pc == RESET_PC + 2 * PC_INC);

        // A resolved nonsequential successor discards the sequential response.
        drive_fetch_response(32'h3333_3333);
        next_pc = 64'h0000_0000_0000_0040;
        tick();
        check("mispredict clears buffered instruction", !inst_valid);
        check("mispredict restarts fetching at resolved target", fetch_pc == next_pc);
        check("wrong-path response is discarded", inst == 32'h2222_2222);

        // The target response can fill an empty slot without commit.
        drive_fetch_response(32'h4444_4444);
        commit = 1'b0;
        tick();
        check("target response refills empty slot", inst_valid);
        check("target response gets target PC", inst_pc == 64'h40);
        check("target response data is retained", inst == 32'h4444_4444);
        check("target response resumes sequential fetching", fetch_pc == 64'h44);

        // Access faults are terminal fetch outcomes and retain their fetch PC.
        drive_no_fetch_outcome();
        fetch_mem_fault = PMP_FETCH;
        fetch_mem_fault_addr = 64'h44;
        next_pc = 64'h44;
        commit = 1'b1;
        tick();
        check("access fault occupies a front-end slot", inst_valid);
        check("access fault is buffered", inst_mem_fault == PMP_FETCH);
        check("access fault address is buffered", inst_mem_fault_addr == 64'h44);
        check("access fault has correct instruction PC", inst_pc == 64'h44);

        // Page faults follow the same outcome path and retain their VA.
        drive_no_fetch_outcome();
        fetch_page_fault = 1'b1;
        fetch_page_fault_addr = 64'h0000_0000_1234_5000;
        next_pc = 64'h48;
        commit = 1'b1;
        tick();
        check("page fault occupies a front-end slot", inst_valid);
        check("page fault is buffered", inst_page_fault);
        check("page fault VA is buffered",
              inst_page_fault_addr == 64'h0000_0000_1234_5000);
        check("page fault fetch PC is retained", inst_pc == 64'h48);

        if (tests_failed == 0) begin
            $display("tb_fetch: all %0d checks passed", tests_run);
            $finish;
        end else
            $fatal(1, "tb_fetch: %0d of %0d checks failed", tests_failed, tests_run);
    end
endmodule : tb_fetch
