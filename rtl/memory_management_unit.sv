import riscv::*;

module memory_management_unit (
    input                     clk,
    input                     rst_n,
    input logic               commit_i,
    input logic               mem_valid_i,
    input ctrl_t              ctrl_mem_i,
    input sfence_sel_t        sfence_sel_i,
    input logic [XLEN-1:0]    addr_i,
    input logic [XLEN-1:0]    pc_i,
    input mem_res_t [MEM_READ_PORTS-1:0] mem_res_i,
    input logic [7:0]          pmp_cfg_i [0:PMP_ENTRY_COUNT-1],
    input logic [XLEN-1:0]     pmp_addr_i [0:PMP_ENTRY_COUNT-1],
    // PTW flush tells the TLBs to stop their active PTWs - asserted on fault/trap
    input logic               ptw_flush_i,
    input machine_privilege_t current_privilege_i,
    input logic [XLEN-1:0]    mstatus_i,
    input logic [XLEN-1:0]    satp_i,
    output mem_req_t [MEM_READ_PORTS-1:0] mem_req_o,
    output logic              data_ptw_stall_o,
    output logic              pc_ptw_stall_o,
    output logic              load_page_fault_o,    // goes to MEM pipeline stage
    output logic              store_page_fault_o,   // goes to MEM pipeline stage
    output logic              fetch_page_fault_o,   // goes back to IF pipeline stage
    output logic [XLEN-1:0]   page_fault_addr_a_o,
    output logic [XLEN-1:0]   page_fault_addr_b_o,
    output mem_fault_t [MEM_READ_PORTS-1:0]   mem_fault_o,
    output logic [MEM_READ_PORTS-1:0][XLEN-1:0] mem_fault_addr_o
);
    logic data_lookup_en, pc_lookup_en,
          data_page_fault, pc_page_fault,
          data_paddr_ready, pc_paddr_ready;

    logic [XLEN-1:0] data_paddr, pc_paddr;
    logic [MEM_READ_PORTS-1:0] tlb_miss, walk_page_fault, tlb_fill_valid,
                               ptw_mem_read, ptw_pte_valid;
    logic [MEM_READ_PORTS-1:0][XLEN-1:0] ptw_mem_addr;
    logic [XLEN-1:0] ptw_vaddr [MEM_READ_PORTS-1:0];
    logic [XLEN-1:0] ptw_pte [MEM_READ_PORTS-1:0];
    tlb_entry_t tlb_fill_entry [MEM_READ_PORTS-1:0];
    mem_req_t [MEM_READ_PORTS-1:0] raw_req;

    for (genvar i = 0; i < MEM_READ_PORTS; i++) begin
        assign ptw_vaddr[i] = raw_req[i].virtual_address;
        assign ptw_pte[i] = mem_res_i[i].data;
        assign ptw_pte_valid[i] = mem_res_i[i].valid;
    end

    page_table_walker page_table_walker (
        .clk              (clk),
        .rst_n            (rst_n),
        .miss_i           (tlb_miss),
        .vaddr_i          (ptw_vaddr),
        .pte_i            (ptw_pte),
        .pte_valid_i      (ptw_pte_valid),
        .satp_i           (satp_i),
        .commit_i         (commit_i),
        .sfence_sel_i     (sfence_sel_i),
        .ptw_flush_i      (ptw_flush_i),
        .ptw_mem_addr_o   (ptw_mem_addr),
        .ptw_mem_read_o   (ptw_mem_read),
        .walk_page_fault_o(walk_page_fault),
        .fill_valid_o     (tlb_fill_valid),
        .fill_entry_o     (tlb_fill_entry)
    );

    translation_lookaside_buffer data_translation_lookaside_buffer (
        .clk                (clk),
        .rst_n              (rst_n),
        .commit_i           (commit_i),
        .sfence_sel_i       (sfence_sel_i),
        .op_i               (raw_req[0].op_original),
        .current_privilege_i(raw_req[0].effective_privilege),
        .lookup_en_i        (data_lookup_en),
        .mstatus_i          (mstatus_i),
        .satp_i             (satp_i),
        .vaddr_i            (raw_req[0].virtual_address),
        .walk_page_fault_i  (walk_page_fault[0]),
        .fill_valid_i       (tlb_fill_valid[0]),
        .fill_entry_i       (tlb_fill_entry[0]),
        .paddr_o            (data_paddr),
        .paddr_ready_o      (data_paddr_ready),
        .ptw_stall_o        (data_ptw_stall_o),
        .miss_o             (tlb_miss[0]),
        .page_fault_o       (data_page_fault)
    );

    translation_lookaside_buffer pc_translation_lookaside_buffer (
        .clk                (clk),
        .rst_n              (rst_n),
        .commit_i           (commit_i),
        .sfence_sel_i       (sfence_sel_i),
        .op_i               (raw_req[1].op_original),
        .current_privilege_i(raw_req[1].effective_privilege),
        .lookup_en_i        (pc_lookup_en),
        .mstatus_i          (mstatus_i),
        .satp_i             (satp_i),
        .vaddr_i            (raw_req[1].virtual_address),
        .walk_page_fault_i  (walk_page_fault[1]),
        .fill_valid_i       (tlb_fill_valid[1]),
        .fill_entry_i       (tlb_fill_entry[1]),
        .paddr_o            (pc_paddr),
        .paddr_ready_o      (pc_paddr_ready),
        .ptw_stall_o        (pc_ptw_stall_o),
        .miss_o             (tlb_miss[1]),
        .page_fault_o       (pc_page_fault)
    );

    physical_memory_checker physical_memory_checker (
        .pmp_cfg_i   (pmp_cfg_i),
        .pmp_addr_i  (pmp_addr_i),
        .mem_req_i   (mem_req_o),
        .fault_o     (mem_fault_o),
        .fault_addr_o(mem_fault_addr_o)
    );

    always_comb begin
        // Assign page fault details, giving priority to fetch > store > load
        page_fault_addr_a_o = '0;
        page_fault_addr_b_o = '0;
        fetch_page_fault_o = '0;
        load_page_fault_o = '0;
        store_page_fault_o = '0;
        if (data_page_fault) begin
            case (raw_req[0].op_original)
                MFETCH : begin
                    page_fault_addr_a_o = raw_req[0].virtual_address;
                    fetch_page_fault_o = '1;
                    $fatal(1, "Memory port 0 should not be fetching instructions!");
                end
                MWRITE : begin
                    page_fault_addr_a_o = raw_req[0].virtual_address;
                    store_page_fault_o = '1;
                end
                MREAD : begin
                    page_fault_addr_a_o = raw_req[0].virtual_address;
                    load_page_fault_o = '1;
                end
                default : ;
            endcase
        end

        if (pc_page_fault) begin
            // Currently, this is guaranteed to be MFETCH
            case (raw_req[1].op_original)
                MFETCH : begin
                    page_fault_addr_b_o = raw_req[1].virtual_address;
                    fetch_page_fault_o = '1;
                end
                MWRITE : begin
                    page_fault_addr_b_o = raw_req[1].virtual_address;
                    store_page_fault_o = '1; 
                    $fatal(1, "Memory port 1 should not be writing data!");
                end
                MREAD : begin
                    page_fault_addr_b_o = raw_req[1].virtual_address;
                    load_page_fault_o = '1;
                    $fatal(1, "Memory port 0 should not be reading data!");
                end
                default : ;
            endcase
        end
    end

    always_comb begin
        mem_req_o = raw_req;

        if (data_lookup_en) begin
            if (data_paddr_ready) begin
                mem_req_o[0].address = data_paddr;
            end else begin
                // Otherwise read a double word from memory if the shared PTW is requesting it
                // (*_ptw_mem_read is the signal which controls that).
                mem_req_o[0].valid               = ptw_mem_read[0];
                mem_req_o[0].address             = ptw_mem_addr[0];
                mem_req_o[0].size                = MEM_DOUBLE;
                mem_req_o[0].op                  = MREAD;
                // Page table walks have an effective privilege (for PTE/PMP) of S
                mem_req_o[0].effective_privilege = S_MODE;
            end
        end

        if (pc_lookup_en) begin
            if (pc_paddr_ready) begin
                mem_req_o[1].address = pc_paddr;
            end else begin
                mem_req_o[1].valid               = ptw_mem_read[1];
                mem_req_o[1].address             = ptw_mem_addr[1];
                mem_req_o[1].size                = MEM_DOUBLE;
                mem_req_o[1].op                  = MREAD;
                mem_req_o[1].effective_privilege = S_MODE;
            end
        end
    end

    always_comb begin
        // defaults
        data_lookup_en = '0;
        pc_lookup_en = '0;

        raw_req[0].address = addr_i;
        raw_req[0].virtual_address = addr_i;
        raw_req[0].size = ctrl_mem_i.mem_size;
        raw_req[0].mem_signed = ctrl_mem_i.mem_signed;
        if (mem_valid_i && ctrl_mem_i.mem_read) begin
            raw_req[0].valid = 1;
            raw_req[0].mem_access_requested = 1;
            raw_req[0].op = MREAD;
            raw_req[0].op_original = MREAD;
        end else if (mem_valid_i && ctrl_mem_i.mem_write) begin
            raw_req[0].valid = 1;
            raw_req[0].mem_access_requested = 1;
            raw_req[0].op = MWRITE;
            raw_req[0].op_original = MWRITE;
        end else begin
            // fallback for no r/w
            raw_req[0].valid = 0;
            raw_req[0].mem_access_requested = 0;
            raw_req[0].op = MREAD;
            raw_req[0].op_original = MREAD;
        end
        raw_req[0].effective_privilege = machine_privilege_t'(current_privilege_i == M_MODE && mstatus_i[MSTATUS_MPRV] ? 
                                mstatus_i[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] :
                                current_privilege_i);

        raw_req[1].valid = 1;
        raw_req[1].mem_access_requested = 1;
        raw_req[1].address = pc_i;
        raw_req[1].virtual_address = pc_i;
        raw_req[1].size = MEM_WORD;
        raw_req[1].mem_signed = MEM_UNSIGNED;
        raw_req[1].op = MFETCH;
        raw_req[1].op_original = MFETCH;
        raw_req[1].effective_privilege = current_privilege_i;

        // Handle virtual addresses
        if (raw_req[0].effective_privilege == M_MODE || satp_mode_t'(satp_i[SATP_MODE_MSB : SATP_MODE_LSB]) == MODE_BARE) begin
            // The data request is valid
        end else if (raw_req[0].mem_access_requested) begin
            // Sv39 virtual memory
            data_lookup_en = '1;
        end

        if (raw_req[1].effective_privilege == M_MODE || satp_mode_t'(satp_i[SATP_MODE_MSB : SATP_MODE_LSB]) == MODE_BARE) begin
        end
        else if (raw_req[1].mem_access_requested) begin
            pc_lookup_en = '1;
        end
        
    end

endmodule : memory_management_unit
