import riscv::*;

module translation_lookaside_buffer (
    input logic                clk,
    input logic                rst_n,
    input mem_op_t             op_i,
    input machine_privilege_t  current_privilege_i,
    input logic                lookup_en_i,
    input logic [XLEN-1:0]     mstatus_i,
    input logic [XLEN-1:0]     satp_i,
    input logic [XLEN-1:0]     vaddr_i,
    input logic [XLEN-1:0]     pte_i,
    input logic                pte_valid_i,
    output logic [XLEN-1:0]    paddr_o,
    output logic [XLEN-1:0]    traversal_addr_o,
    output logic               paddr_ready_o,
    output logic               ptw_stall_o,
    output logic [XLEN-1:0]    ptw_mem_addr_o,
    output logic               ptw_mem_read_o,
    output logic               page_fault_exception_o,
    output logic               access_fault_o
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
    logic global_parent;
    logic [XLEN-1:0] satp_latch, vaddr_latch;

    // mstatus
    logic mstatus_sum, mstatus_mxr;
    assign mstatus_sum = mstatus_i[MSTATUS_SUM];
    assign mstatus_mxr = mstatus_i[MSTATUS_MXR];

    // Normal lookup
    always_comb begin
        pte = '0;
        page_fault_exception_o = '0;
        access_fault_o = '0;
        tlb_hit_idx = '0;
        tlb_hit = '0;
        paddr_o = '0;
        paddr_ready_o = '0;
        ptw_stall_o = '0;
        ptw_mem_addr_o = traversal_addr_o;
        if (lookup_en_i) begin
            ptw_stall_o = '1;
            // All of vaddr[63:39] must equal vaddr[38]
            for (int i = 39; i < 64; i++) begin
                if (vaddr_i[i] != vaddr_i[38]) begin
                    page_fault_exception_o = '1;
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
                    page_fault_exception_o = '1;
                end

                // If we are writing and dirty isn't set, we need to page fault (Svade)
                if (op_i == MWRITE && !pte.dirty) begin
                    page_fault_exception_o = '1;
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
                        page_fault_exception_o = '1;
                    end
                end else begin
                    if (current_privilege_i == U_MODE) begin
                        page_fault_exception_o = '1;
                    end
                end

                // Check rwx
                case (op_i)
                    // A read is allowed if R || (X && MXR)
                    MREAD : if (!pte.read && !(pte.execute && mstatus_mxr)) begin
                        page_fault_exception_o = '1;
                    end
                    MWRITE : if (!pte.write) begin
                        page_fault_exception_o = '1;
                    end
                    MFETCH : if (!pte.execute) begin
                        page_fault_exception_o = '1;
                    end
                    default : ;
                endcase
            end
        end

        // combinational logic for page table walks
        reached_leaf = '0;
        current_pte.vpn = vaddr_latch[38:12];
        current_pte.asid = satp_latch[SATP_ASID_MSB : SATP_ASID_LSB];
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

        // There are certain conditions where we must raise a page fault because of a reserved rwx value.
        if (ptw_stall_o && pte_valid_i) begin
            if (!current_pte.valid ||
                (!current_pte.execute && current_pte.write && !current_pte.read) || // rwx == 010 is reserved
                (current_pte.execute && current_pte.write && !current_pte.read) ||  // rwx == 011 is reserved
                current_level == 3'b111         // we have gone past level == 0
            ) begin
                page_fault_exception_o = '1;
            end

            // rwx != 000 => leaf node
            if (current_pte.read || current_pte.write || current_pte.execute) begin
                reached_leaf = '1;

                // First, make sure this isn't a misaligned superpage
                for (logic [2:0] i = 0; i < current_level; i++) begin
                    if (ppn_index(i, current_pte.ppn) != '0) begin
                        page_fault_exception_o = '1;
                    end
                end
            end
        end

        // If we've encountered a page fault, the address isn't actually ready
        if (page_fault_exception_o) begin
            paddr_ready_o = '0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Invalidate each TLB entry
            for (int i = 0; i < TLB_SIZE; i++) begin
                tlb_entries[i].valid <= '0;
            end
            current_level <= PTE_LEVELS - 1;
            traversal_addr_o <= satp_i[SATP_PPN_MSB : SATP_PPN_LSB] * PAGESIZE;
            ptw_mem_read_o <= '0;
            global_parent <= '0;
            satp_latch <= satp_i;
            vaddr_latch <= vaddr_i;
            // TODO: this is not correct - it needs to be updated with the latest SATP every time it
            // changes. Codex: provide an idea?
        end

        // // If we had a TLB miss, we need to start a PTW
        // if (tlb_state == TLB_IDLE && ptw_stall_o) begin
        //     // TODO: this lengthens the stall by an extra cycle because it has an extra cycle which
        //     // doesn't even execute a memory read (setting traversal_addr_o to its initial value).
        //     // Can this be resolved?
        //     tlb_state <= TLB_PTW;
        //     current_level <= PTE_LEVELS - 1;
        //     // set the traversal address to the start of the page tree
        //     traversal_addr_o <= satp_i[SATP_PPN_MSB : SATP_PPN_LSB] * PAGESIZE;
        //     ptw_mem_read_o <= '1;
        // end

        // At the start of a PTW we need to do a few things.
        // We know a PTW has started if we have a stall and the current level is the max level.
        if (ptw_stall_o && current_level == PTE_LEVELS - 1) begin
            satp_latch <= satp_i;
            vaddr_latch <= vaddr_i;
            ptw_mem_read_o <= '1;
            traversal_addr_o <= satp_i[SATP_PPN_MSB : SATP_PPN_LSB] * PAGESIZE + vpn_index(current_level, vaddr_i[38:12]) * PTESIZE;
        end

        // Continue an existing PTW by going to the next node in the tree if the PTE has been
        // correctly received from memory.
        if (ptw_stall_o && pte_valid_i && !page_fault_exception_o) begin
            ptw_mem_read_o <= '1;
            current_level <= current_level - 1;
            traversal_addr_o <= current_pte.ppn * PAGESIZE + vpn_index(current_level - 1, vaddr_latch[38:12]) * PTESIZE;
            if (current_pte.global_mapping) begin
                global_parent <= '1;
            end
        end

        // On writeback, reset variables
        if (ptw_stall_o && reached_leaf) begin
            current_level <= PTE_LEVELS - 1;
            ptw_mem_read_o <= '0;
            global_parent <= '0;
            if (!page_fault_exception_o) begin
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