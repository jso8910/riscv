import riscv::*;

// One Sv39 page-table walker is shared by the data and instruction TLBs.
module page_table_walker (
    input logic clk,
    input logic rst_n,
    input logic [MEM_READ_PORTS-1:0] miss_i,
    input logic [XLEN-1:0] vaddr_i [MEM_READ_PORTS-1:0],
    input logic [XLEN-1:0] pte_i [MEM_READ_PORTS-1:0],
    input logic [MEM_READ_PORTS-1:0] pte_valid_i,
    input logic [XLEN-1:0] satp_i,
    input logic commit_i,
    input sfence_sel_t sfence_sel_i,
    // PTW flush tells the TLBs to stop their active PTWs - asserted on fault/trap
    input logic ptw_flush_i,
    output logic [MEM_READ_PORTS-1:0][XLEN-1:0] ptw_mem_addr_o,
    output logic [MEM_READ_PORTS-1:0] ptw_mem_read_o,
    output logic [MEM_READ_PORTS-1:0] walk_page_fault_o,
    output logic [MEM_READ_PORTS-1:0] fill_valid_o,
    output tlb_entry_t fill_entry_o [MEM_READ_PORTS-1:0]
);
    // ptw control signals/storage
    logic [2:0] current_level;
    tlb_entry_t current_pte;
    logic reached_leaf;
    logic walk_page_fault;
    logic global_parent, ptw_response_valid;
    logic [XLEN-1:0] traversal_addr;
    // A walk must keep using the translation context that caused its miss,
    // even if the next request arrives while this walk is stalled.
    logic [XLEN-1:0] walk_vaddr_q, walk_satp_q;
    logic sfence_walk_matches;
    logic walk_active_q;
    logic [$clog2(MEM_READ_PORTS)-1:0] walk_port_q;
    logic [$clog2(MEM_READ_PORTS)-1:0] selected_port;

`ifdef FORMAL
    // Portable replacement for $onehot0.  Keep this as an ordinary SV
    // function because the Slang/Yosys bridge does not lower $onehot/$onehot0.
    function automatic logic zero_or_one_hot(
        input logic [MEM_READ_PORTS-1:0] vector
    );
        logic seen_one;
        begin
            seen_one = 1'b0;
            zero_or_one_hot = 1'b1;
            for (int i = 0; i < MEM_READ_PORTS; i++) begin
                if (vector[i]) begin
                    if (seen_one)
                        zero_or_one_hot = 1'b0;
                    seen_one = 1'b1;
                end
            end
        end
    endfunction
`endif

    assign ptw_response_valid = walk_active_q && pte_valid_i[walk_port_q];

    // The instruction port wins a simultaneous initial miss.  Once selected,
    // a walk remains bound to that port until it completes, faults, or flushes.
    always_comb begin
        selected_port = '0;
        for (int i = 0; i < MEM_READ_PORTS; i++) begin
            if (miss_i[i]) begin
                selected_port = $clog2(MEM_READ_PORTS)'(unsigned'(i));
            end
        end
    end

    // A selector built in EX accompanies SFENCE.VMA until writeback.
    always_comb begin
        // An in-flight walk can still resolve to a superpage that covers rs1.
        // Cancel walks for the selected ASID rather than risk a stale refill;
        // this is more conservative than entry invalidation, but safe.  An
        // invalid rs1 VA makes SFENCE.VMA a no-op, including for a walk.
        sfence_walk_matches = commit_i && sfence_sel_i.valid && walk_active_q
            && sfence_sel_i.vaddr_canonical
            && (sfence_sel_i.asid_all
                || walk_satp_q[SATP_ASID_MSB : SATP_ASID_LSB]
                   == sfence_sel_i.asid);
    end

    always_comb begin
        // PTE-response decoding is kept separate from lookup/address
        // generation.  Only this block depends on pte_i.
        reached_leaf = '0;
        walk_page_fault = '0;
        current_pte.vpn = walk_vaddr_q[38:12];
        current_pte.asid = walk_satp_q[SATP_ASID_MSB : SATP_ASID_LSB];
        current_pte.leaf_level = current_level;

        current_pte.ppn = pte_i[walk_port_q][53:10];
        current_pte.accessed = pte_i[walk_port_q][PTE_A];
        current_pte.dirty = pte_i[walk_port_q][PTE_D];
        current_pte.global_mapping = pte_i[walk_port_q][PTE_G] | global_parent;
        current_pte.user = pte_i[walk_port_q][PTE_U];
        current_pte.execute = pte_i[walk_port_q][PTE_X];
        current_pte.write = pte_i[walk_port_q][PTE_W];
        current_pte.read = pte_i[walk_port_q][PTE_R];
        current_pte.valid = pte_i[walk_port_q][PTE_V];

        // There are certain conditions where we must raise a page fault
        // because of an invalid or reserved PTE encoding.
        if (walk_active_q && ptw_response_valid) begin
            if (!current_pte.valid
                || (!current_pte.execute && current_pte.write && !current_pte.read)
                || (current_pte.execute && current_pte.write && !current_pte.read)
                || (pte_i[walk_port_q][PTE_RESERVED_MSB : PTE_RESERVED_LSB] != 0)) begin
                walk_page_fault = '1;
            end

            // rwx != 000 => leaf node.
            if (current_pte.read || current_pte.write || current_pte.execute) begin
                reached_leaf = '1;

                // A superpage PPN must have zeroed lower-level PPN fields.
                for (logic [2:0] i = 0; i < current_level; i++) begin
                    if (ppn_index(i, current_pte.ppn) != '0) begin
                        walk_page_fault = '1;
                    end
                end
            end else if (current_level == '0) begin
                walk_page_fault = '1;
            end else if (current_pte.dirty || current_pte.accessed || current_pte.user) begin
                // Non-leaf D, A, and U bits are reserved in Sv39.
                walk_page_fault = '1;
            end
        end
    end

    always_comb begin
        ptw_mem_addr_o = '0;
        ptw_mem_read_o = '0;
        walk_page_fault_o = '0;
        fill_valid_o = '0;
        for (int i = 0; i < MEM_READ_PORTS; i++) begin
            fill_entry_o[i] = '0;
        end

        if (walk_active_q) begin
            ptw_mem_addr_o[walk_port_q] = traversal_addr;
            ptw_mem_read_o[walk_port_q] = '1;
        end
        if (walk_active_q && walk_page_fault) begin
            walk_page_fault_o[walk_port_q] = '1;
        end
        if (walk_active_q && reached_leaf && !walk_page_fault && !ptw_flush_i) begin
            fill_valid_o[walk_port_q] = '1;
            fill_entry_o[walk_port_q] = current_pte;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_level <= PTE_LEVELS - 1;
            traversal_addr <= '0;
            global_parent <= '0;
            walk_vaddr_q <= '0;
            walk_satp_q <= '0;
            walk_active_q <= '0;
            walk_port_q <= '0;
        end else begin
            // At the start of a PTW we need to do a few things.
            // We know a PTW has just started if we have a stall and ptw_mem_read_o is not yet
            // set.access_fault_o.
            if (!walk_active_q && (|miss_i) && !ptw_flush_i) begin
                walk_active_q <= '1;
                walk_port_q <= selected_port;
                walk_vaddr_q <= vaddr_i[selected_port];
                walk_satp_q <= satp_i;
                traversal_addr <= satp_i[SATP_PPN_MSB : SATP_PPN_LSB] * PAGESIZE + vpn_index(current_level, vaddr_i[selected_port][38:12]) * PTESIZE;
            end

            // Continue an existing PTW by going to the next node in the tree if the PTE has been
            // correctly received from memory.
            if (walk_active_q && !reached_leaf && ptw_response_valid && !walk_page_fault && !ptw_flush_i) begin
                current_level <= current_level - 1;
                traversal_addr <= current_pte.ppn * PAGESIZE + vpn_index(current_level - 1, walk_vaddr_q[38:12]) * PTESIZE;
                if (current_pte.global_mapping) begin
                    global_parent <= '1;
                end
            end

            // On writeback, reset variables
            if (walk_active_q && reached_leaf) begin
                current_level <= PTE_LEVELS - 1;
                walk_active_q <= '0;
                global_parent <= '0;
            end

            // On fault, we need to revert some state
            if (walk_page_fault || ptw_flush_i || sfence_walk_matches) begin
                walk_active_q <= '0;
                current_level <= PTE_LEVELS - 1;
                global_parent <= '0;
            end
        end
    end

    `ifdef FORMAL
    // Why: the PTW is shared by instruction and data translation.  Mixing
    // their contexts, or changing an outstanding PTE address, could refill a
    // TLB with the translation for a different virtual address.
    // What: at most one port can request, refill, or fault at once; an active
    // walk drives its own selected port and traversal address; and a waiting
    // walk keeps its port, VA, SATP, level, and PTE address unchanged.
    // How: zero_or_one_hot checks mutual exclusion.  The final $past-based
    // block compares this cycle's saved walk state with the preceding cycle,
    // but deliberately exempts a PTE response, a flush, and a matching
    // SFENCE.VMA because those are the events allowed to end/change a walk.
    always_ff @(posedge clk) begin
        if (rst_n) begin
            assert (zero_or_one_hot(ptw_mem_read_o));
            assert (zero_or_one_hot(fill_valid_o));
            assert (zero_or_one_hot(walk_page_fault_o));
            if (walk_active_q) begin
                assert (ptw_mem_read_o[walk_port_q]);
                assert (ptw_mem_addr_o[walk_port_q] == traversal_addr);
            end
            if ($past(rst_n) && $past(walk_active_q) && !$past(ptw_response_valid)
                && !$past(ptw_flush_i) && !$past(sfence_walk_matches)) begin
                assert (walk_active_q);
                assert (walk_port_q == $past(walk_port_q));
                assert (walk_vaddr_q == $past(walk_vaddr_q));
                assert (walk_satp_q == $past(walk_satp_q));
                assert (current_level == $past(current_level));
                assert (traversal_addr == $past(traversal_addr));
            end
        end
    end
    `endif
endmodule : page_table_walker
