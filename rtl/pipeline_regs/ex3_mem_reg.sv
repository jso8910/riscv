import riscv::*;

// Pipeline control logic is commented more completely in if_id_reg.sv. The control logic is the
// same between all pipeline registers.

module ex3_mem_reg (
    input logic              clk,
    input logic              rst_n,

    input logic              stall_i,
    input logic              mem_flush_i,
    output logic             ex3_flush_o,
    

    // Upstream interface (execute 3)
    input logic              ex3_valid_i,
    output logic             ex3_ready_o,
    input logic [XLEN-1:0]   ex3_pc_i,
    input logic [XLEN-1:0]   ex3_pred_pc_i,
    input ctrl_t             ex3_ctrl_i,
    input sfence_sel_t       ex3_sfence_sel_i,
    input logic [XLEN-1:0]   ex3_addr_i,
    input logic [XLEN-1:0]   ex3_store_data_i,
    input logic [XLEN-1:0]   ex3_rd_data_i,
    input logic [XLEN-1:0]   ex3_csr_data_write_i,
    input logic [XLEN-1:0]   ex3_csr_operand_i,
    input mem_fault_t        ex3_fetch_mem_fault_i,
    input logic [XLEN-1:0]   ex3_fetch_mem_fault_addr_i,
    input logic              ex3_fetch_page_fault_i,
    input logic [XLEN-1:0]   ex3_fetch_page_fault_addr_i,
    input logic              ex3_address_misaligned_i,

    // Downstream interface (memory)
    input logic               mem_ready_i,
    output logic              mem_valid_o,
    output logic [XLEN-1:0]   mem_pc_o,
    output logic [XLEN-1:0]   mem_pred_pc_o,
    output ctrl_t             mem_ctrl_o,
    output sfence_sel_t       mem_sfence_sel_o,
    output logic [XLEN-1:0]   mem_addr_o,
    output logic [XLEN-1:0]   mem_store_data_o,
    output logic [XLEN-1:0]   mem_rd_data_o,
    output logic [XLEN-1:0]   mem_csr_data_write_o,
    output logic [XLEN-1:0]   mem_csr_operand_o,
    output mem_fault_t        mem_fetch_mem_fault_o,
    output logic [XLEN-1:0]   mem_fetch_mem_fault_addr_o,
    output logic              mem_fetch_page_fault_o,
    output logic [XLEN-1:0]   mem_fetch_page_fault_addr_o,
    output logic              mem_address_misaligned_o
);
    assign ex3_flush_o = mem_flush_i;
    assign ex3_ready_o = (mem_ready_i || !mem_valid_o) && !stall_i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_valid_o <= '0;
            mem_pc_o <= RESET_PC;
            mem_pred_pc_o <= RESET_PC;
            mem_ctrl_o <= '0;
            mem_sfence_sel_o <= '0;
            mem_addr_o <= '0;
            mem_store_data_o <= '0;
            mem_rd_data_o <= '0;
            mem_csr_data_write_o <= '0;
            mem_csr_operand_o <= '0;
            mem_fetch_mem_fault_o <= FAULT_NONE;
            mem_fetch_mem_fault_addr_o <= RESET_PC;
            mem_fetch_page_fault_o <= '0;
            mem_fetch_page_fault_addr_o <= RESET_PC;
            mem_address_misaligned_o <= '0;
        end else if (mem_flush_i) begin
            mem_valid_o <= '0;
        end else begin
            if (ex3_ready_o && ex3_valid_i) begin
                mem_valid_o <= '1;
                mem_pc_o <= ex3_pc_i;
                mem_pred_pc_o <= ex3_pred_pc_i;
                mem_ctrl_o <= ex3_ctrl_i;
                mem_sfence_sel_o <= ex3_sfence_sel_i;
                mem_addr_o <= ex3_addr_i;
                mem_store_data_o <= ex3_store_data_i;
                mem_rd_data_o <= ex3_rd_data_i;
                mem_csr_data_write_o <= ex3_csr_data_write_i;
                mem_csr_operand_o <= ex3_csr_operand_i;
                mem_fetch_mem_fault_o <= ex3_fetch_mem_fault_i;
                mem_fetch_mem_fault_addr_o <= ex3_fetch_mem_fault_addr_i;
                mem_fetch_page_fault_o <= ex3_fetch_page_fault_i;
                mem_fetch_page_fault_addr_o <= ex3_fetch_page_fault_addr_i;
                mem_address_misaligned_o <= ex3_address_misaligned_i;
            end else if (mem_ready_i) begin
                mem_valid_o <= '0;
            end
        end
    end

    `ifdef FORMAL
    // Why: MEM may stall for translation or memory, so the pending operation
    // must remain exactly the same until it is accepted.  What: a flush clears
    // valid, and a stalled MEM entry preserves its PC, control, address, store
    // data, result, and fetch-fault metadata.  How: if $past(mem_ready_i) was
    // low, MEM could not consume the old entry; compare all current outputs to
    // $past outputs rather than using ex3_ready_o, its upstream handshake.
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(mem_flush_i))
                assert (!mem_valid_o);
            if ($past(mem_valid_o) && !$past(mem_ready_i) && !$past(mem_flush_i)) begin
                assert (mem_valid_o);
                assert (mem_pc_o == $past(mem_pc_o));
                assert (mem_pred_pc_o == $past(mem_pred_pc_o));
                assert (mem_ctrl_o == $past(mem_ctrl_o));
                assert (mem_addr_o == $past(mem_addr_o));
                assert (mem_store_data_o == $past(mem_store_data_o));
                assert (mem_rd_data_o == $past(mem_rd_data_o));
                assert (mem_fetch_mem_fault_o == $past(mem_fetch_mem_fault_o));
                assert (mem_fetch_page_fault_o == $past(mem_fetch_page_fault_o));
            end
        end
    end
    `endif
endmodule : ex3_mem_reg
