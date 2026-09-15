`timescale 1ns/1ps

import riscv::*;

// A small shared Sv39 PTW environment.  pte_i is a combinational read port
// into a deliberately ordinary page-table memory; the walker supplies the
// physical PTE address and ptw_mem_read_o is the response-valid qualifier.
module tb_tlb;
    localparam logic [43:0] ROOT_PPN = 44'h001;
    localparam logic [43:0] L1_PPN   = 44'h002;
    localparam logic [43:0] L0_PPN   = 44'h003;
    localparam logic [43:0] LEAF_PPN = 44'h45678;
    localparam logic [XLEN-1:0] FENCE_VA_A = 64'h0000_0000_1234_5678;
    localparam logic [XLEN-1:0] FENCE_VA_B = 64'h0000_0000_2468_a123;

    logic clk;
    logic rst_n;
    logic commit;
    ctrl_t ctrl;
    logic [XLEN-1:0] rs1_data, rs2_data;
    sfence_sel_t sfence_sel;
    mem_op_t op;
    machine_privilege_t privilege;
    logic lookup_en;
    logic [XLEN-1:0] mstatus;
    logic [XLEN-1:0] satp;
    logic [XLEN-1:0] vaddr;
    logic [XLEN-1:0] pte_i;
    logic pte_valid_i;
    logic ptw_flush;
    logic [XLEN-1:0] paddr;
    logic paddr_ready;
    logic ptw_stall;
    logic [XLEN-1:0] ptw_mem_addr;
    logic ptw_mem_read;
    logic page_fault;
    logic tlb_miss;
    logic [MEM_READ_PORTS-1:0] walker_miss, walker_pte_valid,
                               walker_ptw_mem_read, walker_page_fault,
                               walker_fill_valid;
    logic [MEM_READ_PORTS-1:0][XLEN-1:0] walker_ptw_mem_addr;
    logic [XLEN-1:0] walker_vaddr [MEM_READ_PORTS-1:0];
    logic [XLEN-1:0] walker_pte [MEM_READ_PORTS-1:0];
    tlb_entry_t walker_fill_entry [MEM_READ_PORTS-1:0];

    logic [XLEN-1:0] pte_memory [0:2047];
    int tests_run;
    int tests_failed;

    sfence_selector sfence_selector (
        .ctrl_i(ctrl), .rs1_data_i(rs1_data), .rs2_data_i(rs2_data),
        .sfence_sel_o(sfence_sel)
    );

    translation_lookaside_buffer dut (
        .clk(clk), .rst_n(rst_n), .commit_i(commit),
        .sfence_sel_i(sfence_sel), .op_i(op),
        .current_privilege_i(privilege), .lookup_en_i(lookup_en),
        .mstatus_i(mstatus), .satp_i(satp), .vaddr_i(vaddr),
        .walk_page_fault_i(walker_page_fault[0]),
        .fill_valid_i(walker_fill_valid[0]),
        .fill_entry_i(walker_fill_entry[0]),
        .paddr_o(paddr), .paddr_ready_o(paddr_ready),
        .ptw_stall_o(ptw_stall), .miss_o(tlb_miss),
        .page_fault_o(page_fault)
    );

    page_table_walker walker (
        .clk(clk), .rst_n(rst_n), .miss_i(walker_miss),
        .vaddr_i(walker_vaddr), .pte_i(walker_pte),
        .pte_valid_i(walker_pte_valid), .satp_i(satp), .commit_i(commit),
        .sfence_sel_i(sfence_sel), .ptw_flush_i(ptw_flush),
        .ptw_mem_addr_o(walker_ptw_mem_addr),
        .ptw_mem_read_o(walker_ptw_mem_read),
        .walk_page_fault_o(walker_page_fault),
        .fill_valid_o(walker_fill_valid), .fill_entry_o(walker_fill_entry)
    );

    assign walker_miss[0] = tlb_miss;
    assign walker_miss[1] = 1'b0;
    assign walker_vaddr[0] = vaddr;
    assign walker_vaddr[1] = '0;
    assign walker_pte[0] = pte_i;
    assign walker_pte[1] = '0;
    assign walker_pte_valid[0] = pte_valid_i;
    assign walker_pte_valid[1] = 1'b0;
    assign ptw_mem_addr = walker_ptw_mem_addr[0];
    assign ptw_mem_read = walker_ptw_mem_read[0];

    always #5 clk = ~clk;

    always_comb begin
        pte_i = '0;
        if (ptw_mem_addr[2:0] == 3'b000 && ptw_mem_addr[XLEN-1:14] == '0)
            pte_i = pte_memory[ptw_mem_addr[13:3]];
        pte_valid_i = ptw_mem_read;
    end

    function automatic logic [XLEN-1:0] make_pte(
        input logic [43:0] ppn, input logic [7:0] flags
    );
        return (XLEN'(ppn) << 10) | XLEN'(flags);
    endfunction

    function automatic logic [XLEN-1:0] pte_address(
        input logic [43:0] table_ppn, input logic [8:0] index
    );
        return XLEN'(table_ppn) * PAGESIZE + XLEN'(index) * PTESIZE;
    endfunction

    function automatic int pte_index(
        input logic [43:0] table_ppn, input logic [8:0] index
    );
        return (int'(table_ppn) << 9) + int'(index);
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

    task automatic clear_page_tables;
        begin
            for (int i = 0; i < 2048; i++)
                pte_memory[i] = '0;
        end
    endtask

    task automatic reset_tlb;
        begin
            lookup_en = 1'b0;
            commit = 1'b1;
            ptw_flush = 1'b0;
            ctrl = '0;
            rs1_data = '0;
            rs2_data = '0;
            rst_n = 1'b0;
            @(posedge clk);
            #1;
            rst_n = 1'b1;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic map_three_level_page(
        input logic [XLEN-1:0] va, input logic [7:0] leaf_flags
    );
        begin
            pte_memory[pte_index(ROOT_PPN, va[38:30])] =
                make_pte(L1_PPN, 8'b0000_0001);
            pte_memory[pte_index(L1_PPN, va[29:21])] =
                make_pte(L0_PPN, 8'b0000_0001);
            pte_memory[pte_index(L0_PPN, va[20:12])] =
                make_pte(LEAF_PPN, leaf_flags);
        end
    endtask

    task automatic check_three_level_walk(input logic [XLEN-1:0] va);
        begin
            lookup_en = 1'b1;
            #1;
            check("miss stalls the requester", ptw_stall && !paddr_ready && !ptw_mem_read);

            @(posedge clk); #1;
            check("walk issues root PTE read", ptw_mem_read &&
                  ptw_mem_addr == pte_address(ROOT_PPN, va[38:30]));
            @(posedge clk); #1;
            check("walk follows root pointer", ptw_mem_read &&
                  ptw_mem_addr == pte_address(L1_PPN, va[29:21]));
            @(posedge clk); #1;
            check("walk follows level-one pointer", ptw_mem_read &&
                  ptw_mem_addr == pte_address(L0_PPN, va[20:12]));
            @(posedge clk); #1;
            check("leaf PTE fills a translation", !ptw_mem_read && paddr_ready && !page_fault);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b1;
        commit = 1'b1;
        ctrl = '0;
        rs1_data = '0;
        rs2_data = '0;
        op = MREAD;
        privilege = S_MODE;
        lookup_en = 1'b0;
        mstatus = '0;
        satp = (XLEN'(MODE_SV39) << SATP_MODE_LSB) | XLEN'(ROOT_PPN);
        vaddr = '0;
        ptw_flush = 1'b0;
        tests_run = 0;
        tests_failed = 0;

        // Normal three-level walk, then a TLB hit for the same virtual page.
        clear_page_tables();
        vaddr = 64'h0000_0000_1234_5678;
        map_three_level_page(vaddr, 8'b1100_0111); // V,R,W,A,D
        reset_tlb();
        check_three_level_walk(vaddr);
        check("three-level walk returns the expected physical address",
              paddr == {LEAF_PPN, vaddr[11:0]});
        #1;
        check("cached translation no longer stalls", !ptw_stall && paddr_ready && !ptw_mem_read);

        // A VA-scoped SFENCE.VMA drops only the matching cached translation.
        clear_page_tables();
        vaddr = FENCE_VA_A;
        map_three_level_page(FENCE_VA_A, 8'b1100_0111);
        map_three_level_page(FENCE_VA_B, 8'b1100_0111);
        reset_tlb();
        check_three_level_walk(FENCE_VA_A);
        vaddr = FENCE_VA_B;
        check_three_level_walk(FENCE_VA_B);
        ctrl.tlb_invalidate = 1'b1;
        ctrl.rs1_addr = 5'd1;
        ctrl.rs2_addr = '0;
        rs1_data = FENCE_VA_A;
        @(posedge clk); #1;
        ctrl = '0;
        vaddr = FENCE_VA_A;
        #1;
        check("VA-scoped SFENCE.VMA invalidates its matching entry",
              ptw_stall && !paddr_ready);
        vaddr = FENCE_VA_B;
        #1;
        check("VA-scoped SFENCE.VMA retains other entries",
              !ptw_stall && paddr_ready);

        // Once a walk begins, changing the live request must not change the
        // VPN used to select its child PTEs.
        clear_page_tables();
        vaddr = 64'h0000_0000_1234_5678;
        map_three_level_page(vaddr, 8'b1100_0111);
        reset_tlb();
        lookup_en = 1'b1;
        @(posedge clk); #1;
        check("context test issues the original root PTE read", ptw_mem_read &&
              ptw_mem_addr == pte_address(ROOT_PPN, vaddr[38:30]));
        vaddr = 64'h0000_0000_3abc_d000;
        @(posedge clk); #1;
        check("walk keeps the original VPN after live VA changes", ptw_mem_read &&
              ptw_mem_addr == pte_address(L1_PPN, 9'h091));
        ptw_flush = 1'b1;
        @(posedge clk); #1;
        ptw_flush = 1'b0;

        // An invalid rs1 VA makes SFENCE.VMA a no-op.  In particular, it
        // must not cancel an otherwise unrelated in-flight page-table walk.
        clear_page_tables();
        vaddr = FENCE_VA_A;
        map_three_level_page(vaddr, 8'b1100_0111);
        reset_tlb();
        lookup_en = 1'b1;
        @(posedge clk); #1;
        check("noncanonical SFENCE test starts a walk", ptw_mem_read);
        ctrl.tlb_invalidate = 1'b1;
        ctrl.rs1_addr = 5'd1;
        ctrl.rs2_addr = '0;
        rs1_data = 64'h0000_0080_0000_0000;
        @(posedge clk); #1;
        check("noncanonical SFENCE.VMA does not cancel an active walk",
              ptw_mem_read);
        ctrl = '0;
        ptw_flush = 1'b1;
        @(posedge clk); #1;
        ptw_flush = 1'b0;

        // A malformed W-without-R leaf must fault during the walk, not fill.
        clear_page_tables();
        vaddr = 64'h0000_0000_2468_a123;
        map_three_level_page(vaddr, 8'b1100_0101); // V,W,A,D; R is clear
        reset_tlb();
        lookup_en = 1'b1;
        repeat (3) @(posedge clk);
        #1;
        check("reserved W-without-R PTE faults", page_fault && !paddr_ready);
        @(posedge clk); #1;
        check("faulted walk drops its outstanding request", !ptw_mem_read);

        // A non-leaf with U set is reserved by Sv39 and must page-fault.
        clear_page_tables();
        vaddr = 64'h0000_0000_0bad_cafe;
        pte_memory[pte_index(ROOT_PPN, vaddr[38:30])] =
            make_pte(L1_PPN, 8'b0001_0001); // V,U non-leaf
        reset_tlb();
        lookup_en = 1'b1;
        @(posedge clk); #1;
        check("non-leaf U bit is rejected", page_fault);

        // Sv39 addresses must be sign-extended from bit 38 before any walk.
        reset_tlb();
        vaddr = 64'h0000_0080_0000_0000;
        lookup_en = 1'b1;
        #1;
        check("non-canonical Sv39 address faults without a PTW request",
              page_fault && !ptw_mem_read && !paddr_ready);

        if (tests_failed == 0) begin
            $display("tb_tlb: all %0d checks passed", tests_run);
            $finish;
        end else begin
            $fatal(1, "tb_tlb: %0d of %0d checks failed", tests_failed, tests_run);
        end
    end
endmodule : tb_tlb
