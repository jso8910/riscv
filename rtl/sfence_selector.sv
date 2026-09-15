import riscv::*;

// Build the SFENCE.VMA selector in EX, where rs1/rs2 have already passed
// through the normal forwarding network.  Pipeline sfence_sel_o alongside
// ctrl_t; the TLBs use it only when the instruction commits in WB.
module sfence_selector (
    input ctrl_t             ctrl_i,
    input logic [XLEN-1:0]   rs1_data_i,
    input logic [XLEN-1:0]   rs2_data_i,
    output sfence_sel_t      sfence_sel_o
);
    always_comb begin
        sfence_sel_o = '0;
        sfence_sel_o.valid = ctrl_i.tlb_invalidate;

        // The source-register encoding, rather than its value, determines
        // whether the selector is a wildcard.
        sfence_sel_o.vaddr_all = (ctrl_i.rs1_addr == X0);
        sfence_sel_o.asid_all = (ctrl_i.rs2_addr == X0);
        sfence_sel_o.vpn = rs1_data_i[38:12];
        sfence_sel_o.asid = rs2_data_i[SATP_ASID_MSB : SATP_ASID_LSB];

        // Preserve the implementation's existing policy: a non-canonical
        // Sv39 virtual address makes a selectively-addressed fence a no-op.
        sfence_sel_o.vaddr_canonical = sfence_sel_o.vaddr_all;
        if (!sfence_sel_o.vaddr_all) begin
            sfence_sel_o.vaddr_canonical = '1;
            for (int i = 39; i < XLEN; i++) begin
                if (rs1_data_i[i] != rs1_data_i[38]) begin
                    sfence_sel_o.vaddr_canonical = '0;
                end
            end
        end
    end
endmodule : sfence_selector
