import riscv::*;

// Pipeline control logic is commented more completely in if_id_reg.sv. The control logic is the
// same between all pipeline registers.

module ex_mem_reg (
    input logic              clk,
    input logic              rst_n,

    input logic              stall_i,
    input logic              mem_flush_i,
    output logic             ex_flush_o,
    

    // Upstream interface (execute)
    input logic              ex_valid_i,
    output logic             ex_ready_o,
    input logic [XLEN-1:0]   ex_pc_i,
    input logic [XLEN-1:0]   ex_pred_pc_i,
    input ctrl_t             ex_ctrl_i,
    input sfence_sel_t       ex_sfence_sel_i,
    input logic [XLEN-1:0]   ex_addr_i,
    input logic [XLEN-1:0]   ex_store_data_i,
    input logic [XLEN-1:0]   ex_rd_data_i,
    input logic [XLEN-1:0]   ex_csr_data_write_i,
    input logic [XLEN-1:0]   ex_csr_operand_i,
    input mem_fault_t        ex_fetch_mem_fault_i,
    input logic [XLEN-1:0]   ex_fetch_mem_fault_addr_i,
    input logic              ex_fetch_page_fault_i,
    input logic [XLEN-1:0]   ex_fetch_page_fault_addr_i,
    input logic              ex_address_misaligned_i,

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
    assign ex_flush_o = mem_flush_i;
    assign ex_ready_o = (mem_ready_i || !mem_valid_o) && !stall_i;

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
            if (ex_ready_o && ex_valid_i) begin
                mem_valid_o <= '1;
                mem_pc_o <= ex_pc_i;
                mem_pred_pc_o <= ex_pred_pc_i;
                mem_ctrl_o <= ex_ctrl_i;
                mem_sfence_sel_o <= ex_sfence_sel_i;
                mem_addr_o <= ex_addr_i;
                mem_store_data_o <= ex_store_data_i;
                mem_rd_data_o <= ex_rd_data_i;
                mem_csr_data_write_o <= ex_csr_data_write_i;
                mem_csr_operand_o <= ex_csr_operand_i;
                mem_fetch_mem_fault_o <= ex_fetch_mem_fault_i;
                mem_fetch_mem_fault_addr_o <= ex_fetch_mem_fault_addr_i;
                mem_fetch_page_fault_o <= ex_fetch_page_fault_i;
                mem_fetch_page_fault_addr_o <= ex_fetch_page_fault_addr_i;
                mem_address_misaligned_o <= ex_address_misaligned_i;
            end else if (mem_ready_i) begin
                mem_valid_o <= '0;
            end
        end
    end
endmodule : ex_mem_reg
