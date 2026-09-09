`timescale 1ns/1ps

import riscv::*;

module tb_arch_test;
    localparam logic [XLEN-1:0] TOHOST_ADDR = 32'h001f_fff0;
    localparam logic [31:0] HTIF_CONSOLE_WRITE = 32'h0101_0000;
    localparam int DEFAULT_MAX_CYCLES = 2_000_000;

    logic clk;
    logic rst_n;
    string mem_file;
    int max_cycles;
    int cycle;
    logic [63:0] tohost;
    bit finished;

    logic [IALIGN-1:0] inst;
    logic [WWIDTH-1:0] data_mem_rdata;
    logic [WWIDTH-1:0] data_mem_wdata;
    logic [XLEN-1:0] data_mem_addr;
    logic [XLEN-1:0] pc;
    logic [WWIDTH/8-1:0] data_mem_we;

    bit [7:0] memory [];

    riscv_core dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .inst_i          (inst),
        .data_mem_data_i (data_mem_rdata),
        .pc_o            (pc),
        .data_mem_we_o   (data_mem_we),
        .data_mem_addr_o (data_mem_addr),
        .data_mem_data_o (data_mem_wdata)
    );

    always #5 clk = ~clk;

    function automatic logic [7:0] read_memory(input logic [XLEN-1:0] addr);
        begin
            if (addr >= MEM_START_ADDRESS && addr <= MEM_END_ADDRESS) begin
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
                    if (addr >= MEM_START_ADDRESS && addr <= MEM_END_ADDRESS) begin
                        memory[addr - MEM_START_ADDRESS] = value[7:0];
                    end
                    count++;
                end else if (matched == -1) begin
                end else begin
                    $fatal(1, "Malformed memory file %s", path);
                end
            end
            $fclose(fd);
            $display("Loaded %0d bytes", count);
        end
    endtask

    always_comb begin
        inst = '0;
        for (int i = 0; i < IALIGN/8; i++) begin
            inst[i * 8 +: 8] = read_memory(pc + i);
        end
    end

    always_comb begin
        data_mem_rdata = '0;
        for (int i = 0; i < WWIDTH/8; i++) begin
            data_mem_rdata[i * 8 +: 8] = read_memory(data_mem_addr + i);
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            for (int i = 0; i < WWIDTH/8; i++) begin
                if (data_mem_we[i]
                    && data_mem_addr + i >= MEM_START_ADDRESS
                    && data_mem_addr + i <= MEM_END_ADDRESS) begin
                    memory[data_mem_addr + i - MEM_START_ADDRESS] = data_mem_wdata[i * 8 +: 8];
                end
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        max_cycles = DEFAULT_MAX_CYCLES;
        finished = 1'b0;

        if (!$value$plusargs("mem=%s", mem_file)) begin
            $fatal(1, "Missing +mem=<path>");
        end
        if ($value$plusargs("max_cycles=%d", max_cycles)) begin
        end

        memory = new[MEM_END_ADDRESS - MEM_START_ADDRESS + 1];
        load_memory(mem_file);

        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        for (cycle = 0; cycle < max_cycles; cycle++) begin
            @(posedge clk);
            #1;
            tohost = read_tohost();
            if (tohost == 64'd1) begin
                $display("TOHOST PASS 0x%016h cycle %0d", tohost, cycle);
                finished = 1'b1;
                $finish;
                break;
            end else if (tohost == 64'd3) begin
                $display("TOHOST FAIL 0x%016h cycle %0d", tohost, cycle);
                finished = 1'b1;
                $finish;
                break;
            end else if (tohost[63:32] == HTIF_CONSOLE_WRITE) begin
            end else if (tohost[63:32] == 32'h0) begin
            end else if (tohost != 64'd0) begin
                $display("TOHOST UNKNOWN 0x%016h cycle %0d", tohost, cycle);
                finished = 1'b1;
                $finish;
                break;
            end
        end

        if (!finished) begin
            $display("TOHOST TIMEOUT cycle %0d", max_cycles);
            $fatal(1, "DUT did not write tohost");
        end
    end
endmodule : tb_arch_test
