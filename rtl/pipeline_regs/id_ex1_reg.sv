import riscv::*;

// Pipeline control logic is commented more completely in if_id_reg.sv. The control logic is the
// same between all pipeline registers.

module id_ex1_reg (
    input logic              clk,
    input logic              rst_n,

    input logic              stall_i,
    input logic              ex1_flush_i,
    output logic             id_flush_o,

    // Upstream interface (decode)
    input logic              id_valid_i,    // ID has valid data for ID/EX
    output logic             id_ready_o,    // ID/EX ready for new data
    input logic [XLEN-1:0]   id_pc_i,
    input logic [XLEN-1:0]   id_pred_pc_i,
    input ctrl_t             id_ctrl_i,
    input logic [XLEN-1:0]   id_rs1_data_raw_i,
    input logic [XLEN-1:0]   id_rs2_data_raw_i,
    input logic [XLEN-1:0]   id_csr_data_read_raw_i,
    input logic [XLEN-1:0]   id_imm_i,
    input mem_fault_t        id_fetch_mem_fault_i,
    input logic [XLEN-1:0]   id_fetch_mem_fault_addr_i,
    input logic              id_fetch_page_fault_i,
    input logic [XLEN-1:0]   id_fetch_page_fault_addr_i,

    // Downstream interface (execute 1)
    input logic               ex1_ready_i,   // EX1 is ready for new data
    output logic              ex1_valid_o,   // ID/EX1 has valid data for EX1
    output logic [XLEN-1:0]   ex1_pc_o,
    output logic [XLEN-1:0]   ex1_pred_pc_o,
    output ctrl_t             ex1_ctrl_o,
    output logic [XLEN-1:0]   ex1_rs1_data_raw_o,
    output logic [XLEN-1:0]   ex1_rs2_data_raw_o,
    output logic [XLEN-1:0]   ex1_csr_data_read_raw_o,
    output logic [XLEN-1:0]   ex1_imm_o,
    output mem_fault_t        ex1_fetch_mem_fault_o,
    output logic [XLEN-1:0]   ex1_fetch_mem_fault_addr_o,
    output logic              ex1_fetch_page_fault_o,
    output logic [XLEN-1:0]   ex1_fetch_page_fault_addr_o
);
    assign id_flush_o = ex1_flush_i;
    assign id_ready_o = (ex1_ready_i || !ex1_valid_o) && !stall_i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex1_valid_o <= '0;
            ex1_pc_o <= RESET_PC;
            ex1_pred_pc_o <= RESET_PC;
            ex1_ctrl_o <= '0;
            ex1_rs1_data_raw_o <= '0;
            ex1_rs2_data_raw_o <= '0;
            ex1_csr_data_read_raw_o <= '0;
            ex1_imm_o <= '0;
            ex1_fetch_mem_fault_o <= FAULT_NONE;
            ex1_fetch_mem_fault_addr_o <= RESET_PC;
            ex1_fetch_page_fault_o <= '0;
            ex1_fetch_page_fault_addr_o <= RESET_PC;
        end else if (ex1_flush_i) begin
            ex1_valid_o <= '0;
        end else begin
            if (id_ready_o && id_valid_i) begin
                ex1_valid_o <= '1;
                ex1_pc_o <= id_pc_i;
                ex1_pred_pc_o <= id_pred_pc_i;
                ex1_ctrl_o <= id_ctrl_i;
                ex1_rs1_data_raw_o <= id_rs1_data_raw_i;
                ex1_rs2_data_raw_o <= id_rs2_data_raw_i;
                ex1_csr_data_read_raw_o <= id_csr_data_read_raw_i;
                ex1_imm_o <= id_imm_i;
                ex1_fetch_mem_fault_o <= id_fetch_mem_fault_i;
                ex1_fetch_mem_fault_addr_o <= id_fetch_mem_fault_addr_i;
                ex1_fetch_page_fault_o <= id_fetch_page_fault_i;
                ex1_fetch_page_fault_addr_o <= id_fetch_page_fault_addr_i;
            end else if (ex1_ready_i) begin
                ex1_valid_o <= '0;
            end
        end
    end
endmodule : id_ex1_reg
