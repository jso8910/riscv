`timescale 1ns/1ps

import riscv::*;

module tb_memory_controller;
    logic [XLEN-1:0] data_in, mtime, mtimecmp;
    mem_req_t req;
    mem_res_t res;
    logic commit;
    logic [WWIDTH/8-1:0] we;
    logic mtime_we, mtimecmp_we;
    int tests_run, tests_failed;

    memory_controller dut (
        .data_i(data_in), .mtime_i(mtime), .mtimecmp_i(mtimecmp),
        .mem_req_i(req), .commit_i(commit), .res_o(res), .we_o(we),
        .mtime_we_o(mtime_we), .mtimecmp_we_o(mtimecmp_we)
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

    task automatic request(
        input mem_op_t op, input mem_size_t size, input mem_signed_t signedness
    );
        begin
            req = '0;
            req.valid = 1'b1;
            req.op = op;
            req.op_original = op;
            req.size = size;
            req.mem_signed = signedness;
        end
    endtask

    initial begin
        data_in = 64'h89ab_cdef_0123_8080;
        mtime = 64'h1111;
        mtimecmp = 64'h2222;
        req = '0;
        commit = 1'b1;
        tests_run = 0;
        tests_failed = 0;

        #1;
        check("idle has no response or write", !res.valid && we == '0);

        request(MREAD, MEM_BYTE, MEM_SIGNED); #1;
        check("signed byte read returns a valid sign-extended response",
              res.valid && res.data == 64'hffff_ffff_ffff_ff80 && we == '0);
        request(MREAD, MEM_HALF, MEM_UNSIGNED); #1;
        check("unsigned halfword read returns a valid zero-extended response",
              res.valid && res.data == 64'h0000_0000_0000_8080);
        request(MFETCH, MEM_WORD, MEM_UNSIGNED); #1;
        check("fetch is a read response", res.valid && res.data == 64'h0000_0000_0123_8080);

        request(MWRITE, MEM_WORD, MEM_UNSIGNED); #1;
        check("committed word store enables four byte lanes and has no read response",
              we == 8'b0000_1111 && !res.valid);
        commit = 1'b0; #1;
        check("uncommitted store has no side effect", we == '0 && !res.valid);
        commit = 1'b1;

        request(MREAD, MEM_DOUBLE, MEM_UNSIGNED);
        req.address = MTIME_ADDR; #1;
        check("MTIME read bypasses memory data", res.valid && res.data == mtime);
        request(MWRITE, MEM_DOUBLE, MEM_UNSIGNED);
        req.address = MTIMECMP_ADDR; #1;
        check("MTIMECMP store selects its MMIO write enable", mtimecmp_we && we == '0);

        if (tests_failed == 0) begin
            $display("tb_memory_controller: all %0d checks passed", tests_run);
            $finish;
        end else
            $fatal(1, "tb_memory_controller: %0d of %0d checks failed", tests_failed, tests_run);
    end
endmodule : tb_memory_controller
