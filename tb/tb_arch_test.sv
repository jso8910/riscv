`timescale 1ns/1ps

import riscv::*;

module tb_arch_test;
    localparam logic [XLEN-1:0] TOHOST_ADDR = 32'h001f_fff0;
    localparam logic [31:0] HTIF_CONSOLE_WRITE = 32'h0101_0000;
    localparam int DEFAULT_MAX_CYCLES = 2_000_000;
    localparam int TRACE_DEPTH = 32;

    logic clk;
    logic rst_n;
    string mem_file;
    int max_cycles;
    int cycle;
    logic [63:0] tohost;
    bit finished;
    bit debug;
    bit trace_memory;
    logic [63:0] previous_tohost;

    // Keep the last few instructions so failures and timeouts have context even
    // when the test was run without the verbose trace enabled.
    logic [XLEN-1:0] history_pc [TRACE_DEPTH];
    logic [31:0] history_instruction [TRACE_DEPTH];
    int history_cycle [TRACE_DEPTH];
    bit history_valid [TRACE_DEPTH];
    bit history_commit [TRACE_DEPTH];
    bit history_trap [TRACE_DEPTH];
    int history_head;
    int history_count;

    logic [WWIDTH-1:0] inst_mem_data;
    logic [WWIDTH-1:0] data_mem_rdata;
    logic [WWIDTH-1:0] data_mem_wdata;
    logic [XLEN-1:0] data_mem_addr;
    logic [XLEN-1:0] inst_mem_addr;
    logic [WWIDTH/8-1:0] data_mem_we;
    logic mtime_we;
    logic [XLEN-1:0] time_q;

    bit [7:0] memory [];

    riscv_core dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .inst_mem_data_i (inst_mem_data),
        .data_mem_data_i (data_mem_rdata),
        .time_i          (time_q),
        .inst_mem_addr_o (inst_mem_addr),
        .data_mem_we_o   (data_mem_we),
        .data_mem_addr_o (data_mem_addr),
        .data_mem_data_o (data_mem_wdata),
        .mtime_we_o      (mtime_we)
    );

    always #5 clk = ~clk;

    function automatic logic [7:0] read_memory(input logic [XLEN-1:0] addr);
        begin
            if (addr <= MEM_END_ADDRESS) begin
                return memory[addr - MEM_START_ADDRESS];
            end
            return 8'h00;
        end
    endfunction

    function automatic logic [63:0] read_tohost();
        logic [63:0] value;
        begin
            value = '0;
            for (int i = 0; i < 8; i++) begin
                value[i * 8 +: 8] = read_memory(TOHOST_ADDR + i);
            end
            return value;
        end
    endfunction

    function automatic logic [63:0] read_memory64(input logic [XLEN-1:0] addr);
        logic [63:0] value;
        begin
            for (int i = 0; i < 8; i++) begin
                value[i * 8 +: 8] = read_memory(addr + i);
            end
            return value;
        end
    endfunction

    task automatic load_memory(input string path);
        int fd;
        int matched;
        int count;
        int unsigned addr;
        int unsigned value;
        begin
            fd = $fopen(path, "r");
            if (fd == 0) begin
                $fatal(1, "Unable to open memory file %s", path);
            end

            count = 0;
            while (!$feof(fd)) begin
                matched = $fscanf(fd, "%h %h\n", addr, value);
                if (matched == 2) begin
                    if (addr <= MEM_END_ADDRESS) begin
                        memory[addr - MEM_START_ADDRESS] = value[7:0];
                    end
                    count++;
                end else if (matched == -1) begin
                end else begin
                    $fatal(1, "Malformed memory file %s", path);
                end
            end
            $fclose(fd);
            $display("ARCH-TRACE: loaded %0d memory records from %s (range 0x%h-0x%h)",
                     count, path, MEM_START_ADDRESS, MEM_END_ADDRESS);
        end
    endtask

    task automatic dump_history(input string reason);
        int index;
        int oldest;
        begin
            $display("ARCH-TRACE: recent execution history (%s, %0d entries)",
                     reason, history_count);
            oldest = (history_head - history_count + TRACE_DEPTH) % TRACE_DEPTH;
            for (int i = 0; i < history_count; i++) begin
                index = (oldest + i) % TRACE_DEPTH;
                $display("ARCH-TRACE: cycle=%0d pc=0x%016h inst=0x%08h valid=%0b commit=%0b trap=%0b",
                         history_cycle[index], history_pc[index], history_instruction[index],
                         history_valid[index], history_commit[index], history_trap[index]);
            end
            $display("ARCH-TRACE: final pc=0x%016h fetch_pc=0x%016h inst=0x%08h valid=%0b commit=%0b trap=%0b privilege=%0d",
                     dut.id_pc, dut.if_fetch_pc, dut.id_inst, dut.id_valid, dut.wb_retire,
                     dut.wb_trap.is_trap, dut.machine_privilege);
            $display("ARCH-TRACE: final next_pc=0x%016h inst_addr=0x%016h data_addr=0x%016h data_we=0x%0h",
                     dut.redirect_pc, inst_mem_addr, data_mem_addr, data_mem_we);
            $display("ARCH-TRACE: final trap interrupt=%0b exception_cause=%0d tval=0x%016h mepc=0x%016h mtvec=0x%016h",
                     dut.wb_trap.is_interrupt, dut.wb_trap.exception_cause, dut.wb_trap.tval,
                     dut.mepc, dut.mtvec);
            $display("ARCH-TRACE: final tohost=0x%016h time=0x%016h", tohost, time_q);
        end
    endtask

    always_comb begin
        inst_mem_data = '0;
        for (int i = 0; i < IALIGN/8; i++) begin
            inst_mem_data[i * 8 +: 8] = read_memory(inst_mem_addr + i);
        end
    end

    always_comb begin
        data_mem_rdata = '0;
        for (int i = 0; i < WWIDTH/8; i++) begin
            data_mem_rdata[i * 8 +: 8] = read_memory(data_mem_addr + i);
        end
    end

    // Trap and page-fault signals are combinational.  Log them when they assert
    // rather than only at posedge, where the fetch/redirect logic may already
    // have removed the transient assertion.
    always @(dut.wb_trap.is_trap or dut.fetch_page_fault or dut.mem_data_load_page_fault or dut.mem_data_store_page_fault) begin
        if (debug && (dut.wb_trap.is_trap || dut.fetch_page_fault || dut.mem_data_load_page_fault || dut.mem_data_store_page_fault)) begin
            $display("ARCH-TRACE: fault event cycle=%0d pc=0x%016h fetch_pf=%0b load_pf=%0b store_pf=%0b trap=%0b cause=%0d tval=0x%016h satp=0x%016h privilege=%0d mepc=0x%016h sepc=0x%016h",
                     cycle, dut.wb_pc, dut.fetch_page_fault, dut.mem_data_load_page_fault, dut.mem_data_store_page_fault,
                     dut.wb_trap.is_trap, dut.wb_trap.exception_cause, dut.wb_trap.tval, dut.satp,
                     dut.machine_privilege, dut.mepc, dut.sepc);
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            time_q <= '0;
        end else begin
            if (mtime_we)
                time_q <= data_mem_wdata;
            else
                time_q <= time_q + XLEN'(1);

            for (int i = 0; i < WWIDTH/8; i++) begin
                if (data_mem_we[i] && data_mem_addr + i <= MEM_END_ADDRESS) begin
                    memory[data_mem_addr + i - MEM_START_ADDRESS] = data_mem_wdata[i * 8 +: 8];
                end
            end

            history_pc[history_head] = dut.id_pc;
            history_instruction[history_head] = dut.id_inst;
            history_cycle[history_head] = cycle;
            history_valid[history_head] = dut.id_valid;
            history_commit[history_head] = dut.wb_retire;
            history_trap[history_head] = dut.wb_trap.is_trap;
            history_head = (history_head + 1) % TRACE_DEPTH;
            if (history_count < TRACE_DEPTH)
                history_count++;

            if (debug && dut.id_valid) begin
                $display("ARCH-TRACE: cycle=%0d pc=0x%016h inst=0x%08h valid=%0b commit=%0b trap=%0b privilege=%0d next_pc=0x%016h",
                         cycle, dut.id_pc, dut.id_inst, dut.id_valid, dut.wb_retire,
                         dut.wb_trap.is_trap, dut.machine_privilege, dut.redirect_pc);
            end
            if (debug && dut.wb_trap.is_trap) begin
                $display("ARCH-TRACE: trap cycle=%0d interrupt=%0b exception_cause=%0d tval=0x%016h dest_privilege=%0d",
                         cycle, dut.wb_trap.is_interrupt, dut.wb_trap.exception_cause, dut.wb_trap.tval,
                         dut.wb_trap.dest_machine_privilege);
            end
            if (trace_memory && (data_mem_we != '0)) begin
                $display("ARCH-TRACE: store cycle=%0d addr=0x%016h we=0x%0h data=0x%016h",
                         cycle, data_mem_addr, data_mem_we, data_mem_wdata);
            end
            if (debug && dut.id_valid && (dut.id_ctrl.csr_read || dut.id_ctrl.csr_write)) begin
                $display("ARCH-TRACE: csr cycle=%0d addr=0x%03h read=%0b write=%0b rs1=0x%016h value=0x%016h mip=0x%016h mideleg=0x%016h menvcfg=0x%016h stip=%0b",
                         cycle, dut.id_ctrl.csr_addr, dut.id_ctrl.csr_read, dut.id_ctrl.csr_write,
                         dut.id_rs1_data_rf, dut.id_csr_data_read_raw, dut.mip, dut.mideleg, dut.u_csrfile.menvcfg,
                         dut.stip);
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        max_cycles = DEFAULT_MAX_CYCLES;
        finished = 1'b0;
        debug = $test$plusargs("debug") || $test$plusargs("trace");
        trace_memory = $test$plusargs("trace_memory") || debug;
        previous_tohost = '0;
        history_head = 0;
        history_count = 0;

        if (!$value$plusargs("mem=%s", mem_file)) begin
            $fatal(1, "Missing +mem=<path>");
        end
        if ($value$plusargs("max_cycles=%d", max_cycles)) begin
        end

        $display("ARCH-TRACE: starting architecture testbench (max_cycles=%0d debug=%0b trace_memory=%0b)",
                 max_cycles, debug, trace_memory);

        memory = new[MEM_END_ADDRESS - MEM_START_ADDRESS + 1];
        load_memory(mem_file);

        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        for (cycle = 0; cycle < max_cycles; cycle++) begin
            @(posedge clk);
            #1;
            tohost = read_tohost();
            if (tohost != previous_tohost) begin
                if (tohost != 64'd0 || debug)
                    $display("ARCH-TRACE: tohost changed cycle=%0d old=0x%016h new=0x%016h",
                             cycle, previous_tohost, tohost);
                previous_tohost = tohost;
            end
            if (tohost == 64'd1) begin
                $display("ARCH-TRACE: TOHOST PASS 0x%016h cycle %0d", tohost, cycle);
                finished = 1'b1;
                $finish;
                break;
            end else if (tohost == 64'd3) begin
                $display("ARCH-TRACE: TOHOST FAIL 0x%016h cycle %0d", tohost, cycle);
                if ($test$plusargs("failure_scratch")) begin
                    $display("ARCH-TRACE: FAILURE-SCRATCH return=%h expected=%h actual=%h diag=%h",
                             read_memory64(64'h17028), read_memory64(64'h17020),
                             read_memory64(64'h17078), read_memory64(64'h17128));
                end
                dump_history("tohost failure");
                finished = 1'b1;
                $finish;
                break;
            end else if (tohost[63:32] == HTIF_CONSOLE_WRITE) begin
            end else if (tohost[63:32] == 32'h0) begin
            end else if (tohost != 64'd0) begin
                $display("ARCH-TRACE: TOHOST UNKNOWN 0x%016h cycle %0d", tohost, cycle);
                dump_history("unknown tohost");
                finished = 1'b1;
                $finish;
                break;
            end
        end

        if (!finished) begin
            $display("ARCH-TRACE: TOHOST TIMEOUT cycle %0d", max_cycles);
            dump_history("timeout");
            $fatal(1, "DUT did not write tohost");
        end
    end
endmodule : tb_arch_test
