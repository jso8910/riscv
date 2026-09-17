import riscv::*;

module translation_lookaside_buffer (
    input logic                clk,
    input logic                rst_n,
    input logic                commit_i,
    // This EX-derived selector is pipelined to WB.  It is acted on only when
    // commit_i is asserted.
    input sfence_sel_t         sfence_sel_i,
    input mem_op_t             op_i,
    input machine_privilege_t  current_privilege_i,
    input logic                lookup_en_i,
    input logic [XLEN-1:0]     mstatus_i,
    input logic [XLEN-1:0]     satp_i,
    input logic [XLEN-1:0]     vaddr_i,
    input logic                walk_page_fault_i,
    input logic                fill_valid_i,
    input tlb_entry_t          fill_entry_i,
    output logic [XLEN-1:0]    paddr_o,
    output logic               paddr_ready_o,
    output logic               ptw_stall_o,
    output logic               miss_o,
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
    logic found;
    logic lookup_page_fault;
    tlb_entry_t pte;
    logic [TLB_SIZE-1:0] sfence_entry_matches;

    // SFENCE.VMA is selective by virtual address and ASID.  The selector is
    // reduced in EX so no full source operands must reach writeback.
    always_comb begin
        for (int i = 0; i < TLB_SIZE; i++) begin
            sfence_entry_matches[i] = commit_i && sfence_sel_i.valid
                && sfence_sel_i.vaddr_canonical
                && (sfence_sel_i.vaddr_all
                    || (vpn_mask(tlb_entries[i].leaf_level, tlb_entries[i].vpn)
                        == vpn_mask(tlb_entries[i].leaf_level, sfence_sel_i.vpn)))
                && (sfence_sel_i.asid_all
                    || (!tlb_entries[i].global_mapping
                        && tlb_entries[i].asid
                           == sfence_sel_i.asid));
        end
    end

    // mstatus
    logic mstatus_sum, mstatus_mxr;
    assign mstatus_sum = mstatus_i[MSTATUS_SUM];
    assign mstatus_mxr = mstatus_i[MSTATUS_MXR];

    // The lookup path deliberately has no dependency on PTE responses.  It
    // produces the request-side translation result; the shared PTW consumes a
    // PTE response separately.  This keeps a read response from feeding back
    // combinationally into its own request address.
    always_comb begin
        pte = '0;
        lookup_page_fault = '0;
        tlb_hit_idx = '0;
        tlb_hit = '0;
        paddr_o = '0;
        paddr_ready_o = '0;
        ptw_stall_o = '0;
        miss_o = '0;
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
                    default : begin
                        // Every TLB lookup must be a read, write, or fetch.
                        assert (1'b0);
                    end
                endcase
            end
        end

        // A lookup fault means this request has no usable physical address.
        // A PTW fault is necessarily on a miss, where paddr_ready_o is already
        // low, so it need not feed back into the request-side output.
        if (lookup_page_fault) begin
            paddr_ready_o = '0;
        end

        if (lookup_en_i && !tlb_hit && !lookup_page_fault) begin
            miss_o = '1;
        end

        // A lookup or PTW fault is a completed translation result, not an
        // outstanding walk.  Release the pipeline so MEM/WB can capture the
        // fault and the trap controller can redirect; otherwise the faulting
        // memory operation remains stalled forever in MEM.
        if (lookup_page_fault || walk_page_fault_i) begin
            ptw_stall_o = '0;
            miss_o = '0;
        end
    end

    assign page_fault_o = lookup_page_fault | walk_page_fault_i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Invalidate each TLB entry
            for (int i = 0; i < TLB_SIZE; i++) begin
                tlb_entries[i].valid <= '0;
            end
        end else begin
            // On writeback, reset variables
            if (fill_valid_i) begin
                // Look for a free TLB entry
                // TODO: make this part better. Overall need a better allocation algorithm
                found = '0;
                for (int i = 0; i < TLB_SIZE; i++) begin
                    if (!tlb_entries[i].valid && !found) begin
                        tlb_entries[i] <= fill_entry_i;
                        found = '1;
                    end
                end
                // If we don't find a suitable location, we can replace the first element of the TLB
                // TODO: this isn't ideal, because it will result in bad outcomes with temporal
                // locality. If you're switching between two pages, their TLB entries will
                // constantly overwrite each other.
                if (!found) begin
                    tlb_entries[0] <= fill_entry_i;
                end
            end

            // Keep this after writeback, so a fence also wins if a PTE response
            // and SFENCE.VMA occur in the same cycle.
            for (int i = 0; i < TLB_SIZE; i++) begin
                if (sfence_entry_matches[i]) begin
                    tlb_entries[i].valid <= '0;
                end
            end
        end
    end

    `ifdef FORMAL
    // Why: a translation must have one unambiguous outcome.  Treating a fault
    // as both complete and stalled can deadlock the pipeline; retaining an
    // SFENCE.VMA-matched entry can use a stale mapping after software changes
    // page tables.
    // What: a page fault has neither a usable address nor an outstanding miss;
    // a ready physical address comes only from a permission-checked hit; and
    // a committed matching SFENCE.VMA invalidates its entry next cycle.
    // How: check the mutually exclusive output flags directly, then use
    // $past(sfence_entry_matches[i]) to require the corresponding valid bit
    // to be clear in the following sampled state.
    always_ff @(posedge clk) begin
        if (rst_n) begin
            if (lookup_en_i && page_fault_o) begin
                assert (!paddr_ready_o);
                assert (!miss_o);
                assert (!ptw_stall_o);
            end
            if (lookup_en_i && paddr_ready_o) begin
                assert (tlb_hit);
                assert (!page_fault_o);
                assert (!miss_o);
                assert (!ptw_stall_o);
            end
            for (int i = 0; i < TLB_SIZE; i++) begin
                if ($past(rst_n) && $past(sfence_entry_matches[i]))
                    assert (!tlb_entries[i].valid);
            end
        end
    end
    `endif
endmodule : translation_lookaside_buffer
