import riscv::*;

module translation_lookaside_buffer (
    input logic                clk,
    input logic                rst_n,
    input logic                commit_i,
    input ctrl_t               ctrl_i,
    input logic [XLEN-1:0]     rs1_data_i,
    input logic [XLEN-1:0]     rs2_data_i,
    input mem_op_t             op_i,
    input machine_privilege_t  current_privilege_i,
    input logic                lookup_en_i,
    input logic [XLEN-1:0]     mstatus_i,
    input logic [XLEN-1:0]     satp_i,
    input logic [XLEN-1:0]     vaddr_i,
    input logic [XLEN-1:0]     pte_i,
    input logic                pte_valid_i,
    input logic                ptw_flush_i,
    output logic [XLEN-1:0]    paddr_o,
    output logic               paddr_ready_o,
    output logic               ptw_stall_o,
    output logic [XLEN-1:0]    ptw_mem_addr_o,
    output logic               ptw_mem_read_o,
    output logic               page_fault_o
);
    // Translation lookaside buffer which support Sv39.
    // For each page, stores:
    //  - VPN[2:0], ASID from SATP, and the final leaf level
    //  - DAGUXWRV
    //  - PPN[2:0]

    tlb_entry_t tlb_entries [0:TLB_SIZE-1];

    // control signals
    logic tlb_hit;
    logic [$clog2(TLB_SIZE)-1:0] tlb_hit_idx;

    // ptw control signals/storage
    logic [2:0] current_level;
    tlb_entry_t current_pte, pte;
    logic reached_leaf, found;
    logic lookup_page_fault, walk_page_fault;
    logic global_parent, ptw_response_valid;
    logic [XLEN-1:0] traversal_addr;
    // A walk must keep using the translation context that caused its miss,
    // even if the next request arrives while this walk is stalled.
    logic [XLEN-1:0] walk_vaddr_q, walk_satp_q;
    logic sfence_vaddr_canonical, sfence_walk_matches;
    logic [TLB_SIZE-1:0] sfence_entry_matches;

    assign ptw_response_valid = ptw_mem_read_o && pte_valid_i;

    // SFENCE.VMA is selective by virtual address (rs1) and ASID (rs2).
    // x0 is a selector meaning "all", rather than a register value of zero.
    always_comb begin
        sfence_vaddr_canonical = '1;
        for (int i = 39; i < 64; i++) begin
            if (rs1_data_i[i] != rs1_data_i[38]) begin
                sfence_vaddr_canonical = '0;
            end
        end

        for (int i = 0; i < TLB_SIZE; i++) begin
            sfence_entry_matches[i] = commit_i && ctrl_i.tlb_invalidate
                && (ctrl_i.rs1_addr == '0
                    || (sfence_vaddr_canonical
                        && vpn_mask(tlb_entries[i].leaf_level, tlb_entries[i].vpn)
                           == vpn_mask(tlb_entries[i].leaf_level, rs1_data_i[38:12])))
                && (ctrl_i.rs2_addr == '0
                    || (!tlb_entries[i].global_mapping
                        && tlb_entries[i].asid
                           == rs2_data_i[SATP_ASID_MSB : SATP_ASID_LSB]));
        end

        // An in-flight walk can still resolve to a superpage that covers rs1.
        // Cancel walks for the selected ASID rather than risk a stale refill;
        // this is more conservative than entry invalidation, but safe.  An
        // invalid rs1 VA makes SFENCE.VMA a no-op, including for a walk.
        sfence_walk_matches = commit_i && ctrl_i.tlb_invalidate && ptw_mem_read_o
            && (ctrl_i.rs1_addr == '0 || sfence_vaddr_canonical)
            && (ctrl_i.rs2_addr == '0
                || walk_satp_q[SATP_ASID_MSB : SATP_ASID_LSB]
                   == rs2_data_i[SATP_ASID_MSB : SATP_ASID_LSB]);
    end

    // mstatus
    logic mstatus_sum, mstatus_mxr;
    assign mstatus_sum = mstatus_i[MSTATUS_SUM];
    assign mstatus_mxr = mstatus_i[MSTATUS_MXR];

    // The lookup path deliberately has no dependency on pte_i.  It produces
    // the request-side translation result, while the separate PTW block below
    // consumes a PTE response.  This keeps a read response from feeding back
    // combinationally into its own request address.
    always_comb begin
        pte = '0;
        lookup_page_fault = '0;
        tlb_hit_idx = '0;
        tlb_hit = '0;
        paddr_o = '0;
        paddr_ready_o = '0;
        ptw_stall_o = '0;
        ptw_mem_addr_o = traversal_addr;
        if (lookup_en_i) begin
            ptw_stall_o = '1;
            // All of vaddr[63:39] must equal vaddr[38]
            for (int i = 39; i < 64; i++) begin
                if (vaddr_i[i] != vaddr_i[38]) begin
                    lookup_page_fault = '1;
                end
            end
            for (int i = 0; i < TLB_SIZE; i++) begin
                // If this entry isn't valid (eg it's not filled with real data), ignore it
                if (!tlb_entries[i].valid) begin
                    continue;
                end
                // If asid doesn't match, then we can only match if global is true
                if (!tlb_entries[i].global_mapping && tlb_entries[i].asid != satp_i[SATP_ASID_MSB : SATP_ASID_LSB]) begin
                    continue;
                end

                // If the VPNs match, we have a TLB hit!
                if (
                    vpn_mask(tlb_entries[i].leaf_level,  tlb_entries[i].vpn) ==
                    vpn_mask(tlb_entries[i].leaf_level,  vaddr_i[38:12])
                ) begin
                    tlb_hit = '1;
                    tlb_hit_idx = ($clog2(TLB_SIZE))'(unsigned'(i));
                    break;
                end
            end

            // If we got a hit, return the physical address
            if (tlb_hit) begin
                pte = tlb_entries[tlb_hit_idx];
                ptw_stall_o = '0;
                paddr_o = ppn_to_addr(
                    pte.leaf_level,
                    vaddr_i,
                    pte.ppn
                );
                paddr_ready_o = '1;

                // If accessed isn't set, we need to page fault (Svade)
                if (!pte.accessed) begin
                    lookup_page_fault = '1;
                end

                // If we are writing and dirty isn't set, we need to page fault (Svade)
                if (op_i == MWRITE && !pte.dirty) begin
                    lookup_page_fault = '1;
                end

                // Check the U bit
                if (pte.user) begin
                    // The second condition is technically not needed, but could be useful for backwards
                    // compatibility if/when hypervisor support is added.
                    // We have a page fault if you try to access a user page in S_MODE unless SUM is
                    // set.
                    // However, regardless, there is a fault if you are in S mode and you try to
                    // execute a user page.
                    if (
                        (current_privilege_i == S_MODE && (!mstatus_sum || op_i == MFETCH)) ||
                        current_privilege_i > S_MODE
                    ) begin
                        lookup_page_fault = '1;
                    end
                end else begin
                    if (current_privilege_i == U_MODE) begin
                        lookup_page_fault = '1;
                    end
                end

                // Check rwx
                case (op_i)
                    // A read is allowed if R || (X && MXR)
                    MREAD : if (!pte.read && !(pte.execute && mstatus_mxr)) begin
                        lookup_page_fault = '1;
                    end
                    MWRITE : if (!pte.write) begin
                        lookup_page_fault = '1;
                    end
                    MFETCH : if (!pte.execute) begin
                        lookup_page_fault = '1;
                    end
                    default : ;
                endcase
            end
        end

        // A lookup fault means this request has no usable physical address.
        // A PTW fault is necessarily on a miss, where paddr_ready_o is already
        // low, so it need not feed back into the request-side output.
        if (lookup_page_fault) begin
            paddr_ready_o = '0;
        end
    end

    always_comb begin
        // PTE-response decoding is kept separate from lookup/address
        // generation.  Only this block depends on pte_i.
        reached_leaf = '0;
        walk_page_fault = '0;
        current_pte.vpn = walk_vaddr_q[38:12];
        current_pte.asid = walk_satp_q[SATP_ASID_MSB : SATP_ASID_LSB];
        current_pte.leaf_level = current_level;

        current_pte.ppn = pte_i[53:10];
        current_pte.accessed = pte_i[PTE_A];
        current_pte.dirty = pte_i[PTE_D];
        current_pte.global_mapping = pte_i[PTE_G] | global_parent;
        current_pte.user = pte_i[PTE_U];
        current_pte.execute = pte_i[PTE_X];
        current_pte.write = pte_i[PTE_W];
        current_pte.read = pte_i[PTE_R];
        current_pte.valid = pte_i[PTE_V];

        // There are certain conditions where we must raise a page fault
        // because of an invalid or reserved PTE encoding.
        if (ptw_stall_o && ptw_response_valid) begin
            if (!current_pte.valid
                || (!current_pte.execute && current_pte.write && !current_pte.read)
                || (current_pte.execute && current_pte.write && !current_pte.read)
                || (pte_i[PTE_RESERVED_MSB : PTE_RESERVED_LSB] != 0)) begin
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

    assign page_fault_o = lookup_page_fault | walk_page_fault;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Invalidate each TLB entry
            for (int i = 0; i < TLB_SIZE; i++) begin
                tlb_entries[i].valid <= '0;
            end
            current_level <= PTE_LEVELS - 1;
            traversal_addr <= '0;
            ptw_mem_read_o <= '0;
            global_parent <= '0;
            walk_vaddr_q <= '0;
            walk_satp_q <= '0;
        end

        // At the start of a PTW we need to do a few things.
        // We know a PTW has just started if we have a stall and ptw_mem_read_o is not yet
        // set.access_fault_o.
        if (ptw_stall_o && !ptw_mem_read_o && !page_fault_o && !ptw_flush_i) begin
            ptw_mem_read_o <= '1;
            walk_vaddr_q <= vaddr_i;
            walk_satp_q <= satp_i;
            traversal_addr <= satp_i[SATP_PPN_MSB : SATP_PPN_LSB] * PAGESIZE + vpn_index(current_level, vaddr_i[38:12]) * PTESIZE;
        end

        // Continue an existing PTW by going to the next node in the tree if the PTE has been
        // correctly received from memory.
        if (ptw_stall_o && !reached_leaf && ptw_response_valid && !page_fault_o && !ptw_flush_i) begin
            ptw_mem_read_o <= '1;
            current_level <= current_level - 1;
            traversal_addr <= current_pte.ppn * PAGESIZE + vpn_index(current_level - 1, walk_vaddr_q[38:12]) * PTESIZE;
            if (current_pte.global_mapping) begin
                global_parent <= '1;
            end
        end

        // On writeback, reset variables
        if (ptw_stall_o && reached_leaf) begin
            current_level <= PTE_LEVELS - 1;
            ptw_mem_read_o <= '0;
            global_parent <= '0;
            if (!page_fault_o && !ptw_flush_i) begin
                // Look for a free TLB entry
                // TODO: make this part better. Overall need a better allocation algorithm
                found = '0;
                for (int i = 0; i < TLB_SIZE; i++) begin
                    if (!tlb_entries[i].valid && !found) begin
                        tlb_entries[i] <= current_pte;
                        found = '1;
                    end
                end
                // If we don't find a suitable location, we can replace the first element of the TLB
                // TODO: this isn't ideal, because it will result in bad outcomes with temporal
                // locality. If you're switching between two pages, their TLB entries will
                // constantly overwrite each other.
                if (!found) begin
                    tlb_entries[0] <= current_pte;
                end
            end
        end

        // On fault, we need to revert some state
        if (page_fault_o || ptw_flush_i || sfence_walk_matches) begin
            ptw_mem_read_o <= '0;
            current_level <= PTE_LEVELS - 1;
            global_parent <= '0;
        end

        // Keep this after writeback, so a fence also wins if a PTE response
        // and SFENCE.VMA occur in the same cycle.
        for (int i = 0; i < TLB_SIZE; i++) begin
            if (sfence_entry_matches[i]) begin
                tlb_entries[i].valid <= '0;
            end
        end
    end
endmodule : translation_lookaside_buffer

function automatic [26:0] vpn_mask(
    input logic [2:0] leaf_level,
    input [26:0] vpn
);
    if (leaf_level == 0) begin
        return vpn;
    end else if (leaf_level == 1) begin
        return {vpn[26:9], 9'b0};
    end else if (leaf_level == 2) begin
        return {vpn[26:18], 18'b0};
    end
    // fallback
    return vpn;
endfunction

function automatic [8:0] vpn_index(
    input logic [2:0] level,
    input [26:0] vpn
);
    if (level == 0) begin
        return vpn[8:0];
    end else if (level == 1) begin
        return vpn[17:9];
    end else if (level == 2) begin
        return vpn[26:18];
    end
    // fallback
    return vpn[8:0];
endfunction

function automatic [43:0] ppn_index(
    input logic [2:0] level,
    input [43:0] ppn
);
    if (level == 0) begin
        return 44'(ppn[8:0]);
    end else if (level == 1) begin
        return 44'(ppn[17:9]);
    end else if (level == 2) begin
        return 44'(ppn[43:18]);
    end
    // fallback
    return 44'(ppn[8:0]);
endfunction

function automatic logic [XLEN-1:0] ppn_to_addr(
    input logic [2:0] leaf_level,
    input logic [XLEN-1:0] vaddr,
    input logic [43:0] ppn
);
    if (leaf_level == 0) begin
        // 56 bit physical address, zero extended to XLEN (64)
        return {8'b0, ppn, vaddr[11:0]};
    end else if (leaf_level == 1) begin
        // This is a megapage - the first VPN field is part of the offset
        return {8'b0, ppn[43:9], vaddr[20:0]};
    end else if (leaf_level == 2) begin
        // This is a gigapage - the first two VPN fields are part of the offset
        return {8'b0, ppn[43:18], vaddr[29:0]};
    end
    // fallback, should not be accessed
    return {8'b0, ppn, vaddr[11:0]};
endfunction
