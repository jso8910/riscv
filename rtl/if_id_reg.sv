import riscv::*;

module if_id_reg (
    input logic              clk,
    input logic              rst_n,

    // signal to initiate a stall from this pipeline register, propagating backwards
    input logic              stall_i,
    input logic              id_flush_i,
    output logic             if_flush_o,

    // Upstream interface (fetch)
    input logic              if_valid_i,    // IF has valid data for IF/ID
    output logic             if_ready_o,    // IF/ID ready for new data
    input logic [XLEN-1:0]   if_pc_i,
    input logic [XLEN-1:0]   if_pred_pc_i,
    input logic [IALIGN-1:0] if_inst_i,
    input mem_fault_t        if_fetch_mem_fault_i,
    input logic [XLEN-1:0]   if_fetch_mem_fault_addr_i,
    input logic              if_fetch_page_fault_i,
    input logic [XLEN-1:0]   if_fetch_page_fault_addr_i,

    // Downstream interface (decode)
    input logic               id_ready_i,   // Decode stage is ready for new data
    output logic              id_valid_o,   // IF/ID has valid data for decode
    output logic [XLEN-1:0]   id_pc_o,
    output logic [XLEN-1:0]   id_pred_pc_o,
    output logic [IALIGN-1:0] id_inst_o,
    output mem_fault_t        id_fetch_mem_fault_o,
    output logic [XLEN-1:0]   id_fetch_mem_fault_addr_o,
    output logic              id_fetch_page_fault_o,
    output logic [XLEN-1:0]   id_fetch_page_fault_addr_o
);
    assign if_flush_o = id_flush_i;
    // We want to put new data into the register under two conditions:
    //  1. The decoder is done processing the current contents; or
    //  2. The data currently in the register is not valid, in which case the decoder can't be doing
    //     any meaningful work on it.
    assign if_ready_o = (id_ready_i || !id_valid_o) && !stall_i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_valid_o <= '0;
            id_pc_o <= RESET_PC;
            id_pred_pc_o <= RESET_PC;
            id_inst_o <= RISCV_NOP;
            id_fetch_mem_fault_o <= FAULT_NONE;
            id_fetch_mem_fault_addr_o <= RESET_PC;
            id_fetch_page_fault_o <= '0;
            id_fetch_page_fault_addr_o <= RESET_PC;
        end else if (id_flush_i) begin
            id_valid_o <= '0;
        end else begin
            // We put new data iff the current data is done being processed (and no stall) and the
            // data in the fetch unit is valid
            if (if_ready_o && if_valid_i) begin
                id_valid_o <= '1;
                id_pc_o <= if_pc_i;
                id_pred_pc_o <= if_pred_pc_i;
                id_inst_o <= if_inst_i;
                id_fetch_mem_fault_o <= if_fetch_mem_fault_i;
                id_fetch_mem_fault_addr_o <= if_fetch_mem_fault_addr_i;
                id_fetch_page_fault_o <= if_fetch_page_fault_i;
                id_fetch_page_fault_addr_o <= if_fetch_page_fault_addr_i;
            // If id is done but for some reason the fetch unit isn't ready (external stall signal,
            // etc) then we want to insert a bubble
            end else if (id_ready_i) begin
                id_valid_o <= '0;
            end
            // If id_ready_i == 0 AND if_ready_o == 0, the state holds because the decoder is still
            // working on the data in this register.
        end
    end

endmodule : if_id_reg
