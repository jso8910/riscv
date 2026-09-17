import riscv::*;

// Pipeline control logic is commented more completely in if_id_reg.sv. The control logic is the
// same between all pipeline registers.

module mem_wb_reg (
    input logic              clk,
    input logic              rst_n,

    input logic              stall_i,
    input logic              wb_flush_i,
    output logic             mem_flush_o,

    input mem_res_t          mem_data_res_i,

    // Upstream interface (execute)
    input logic              mem_valid_i,
    output logic             mem_ready_o,
    input logic [XLEN-1:0]   mem_pc_i,
    input logic [XLEN-1:0]   mem_pred_pc_i,
    input ctrl_t             mem_ctrl_i,
    input sfence_sel_t       mem_sfence_sel_i,
    input logic [XLEN-1:0]   mem_rd_data_i,
    input logic [XLEN-1:0]   mem_csr_data_write_i,
    input logic [XLEN-1:0]   mem_csr_operand_i,
    input mem_fault_t        mem_fetch_mem_fault_i,
    input logic [XLEN-1:0]   mem_fetch_mem_fault_addr_i,
    input logic              mem_fetch_page_fault_i,
    input logic [XLEN-1:0]   mem_fetch_page_fault_addr_i,
    input mem_fault_t        mem_data_mem_fault_i,
    input logic [XLEN-1:0]   mem_data_mem_fault_addr_i,
    input logic              mem_data_store_page_fault_i,
    input logic              mem_data_load_page_fault_i,
    input logic [XLEN-1:0]   mem_data_page_fault_addr_i,
    input logic              mem_address_misaligned_i,

    // Downstream interface (memory)
    output logic             wb_valid_o,
    input logic              wb_ready_i,
    output logic [XLEN-1:0]  wb_pc_o,
    output logic [XLEN-1:0]  wb_pred_pc_o,
    output ctrl_t            wb_ctrl_o,
    output sfence_sel_t      wb_sfence_sel_o,
    output logic [XLEN-1:0]  wb_rd_data_o,
    output logic [XLEN-1:0]  wb_csr_data_write_o,
    output logic [XLEN-1:0]  wb_csr_operand_o,
    output mem_fault_t       wb_fetch_mem_fault_o,
    output logic [XLEN-1:0]  wb_fetch_mem_fault_addr_o,
    output logic             wb_fetch_page_fault_o,
    output logic [XLEN-1:0]  wb_fetch_page_fault_addr_o,
    output mem_fault_t       wb_data_mem_fault_o,
    output logic [XLEN-1:0]  wb_data_mem_fault_addr_o,
    output logic             wb_data_store_page_fault_o,
    output logic             wb_data_load_page_fault_o,
    output logic [XLEN-1:0]  wb_data_page_fault_addr_o,
    output logic             wb_address_misaligned_o
);
    assign mem_flush_o = wb_flush_i;
    assign mem_ready_o = (wb_ready_i || !wb_valid_o) && !stall_i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_valid_o <= '0;
            wb_pc_o <= RESET_PC;
            wb_pred_pc_o <= RESET_PC;
            wb_ctrl_o <= '0;
            wb_sfence_sel_o <= '0;
            wb_rd_data_o <= '0;
            wb_csr_data_write_o <= '0;
            wb_csr_operand_o <= '0;
            wb_fetch_mem_fault_o <= FAULT_NONE;
            wb_fetch_mem_fault_addr_o <= RESET_PC;
            wb_fetch_page_fault_o <= '0;
            wb_fetch_page_fault_addr_o <= RESET_PC;
            wb_data_mem_fault_o <= FAULT_NONE;
            wb_data_mem_fault_addr_o <= RESET_PC;
            wb_data_store_page_fault_o <= '0;
            wb_data_load_page_fault_o <= '0;
            wb_data_page_fault_addr_o <= '0;
            wb_address_misaligned_o <= '0;
        end else if (wb_flush_i) begin
            wb_valid_o <= '0;
        end else begin
            if (mem_ready_o && mem_valid_i) begin
                wb_valid_o <= '1;
                wb_pc_o <= mem_pc_i;
                wb_pred_pc_o <= mem_pred_pc_i;
                wb_ctrl_o <= mem_ctrl_i;
                wb_sfence_sel_o <= mem_sfence_sel_i;
                wb_rd_data_o <= mem_ctrl_i.wb_sel == WB_MEM ? mem_data_res_i.data : mem_rd_data_i;
                wb_csr_data_write_o <= mem_csr_data_write_i;
                wb_csr_operand_o <= mem_csr_operand_i;
                wb_fetch_mem_fault_o <= mem_fetch_mem_fault_i;
                wb_fetch_mem_fault_addr_o <= mem_fetch_mem_fault_addr_i;
                wb_fetch_page_fault_o <= mem_fetch_page_fault_i;
                wb_fetch_page_fault_addr_o <= mem_fetch_page_fault_addr_i;
                wb_data_mem_fault_o <= mem_data_mem_fault_i;
                wb_data_mem_fault_addr_o <= mem_data_mem_fault_addr_i;
                wb_data_store_page_fault_o <= mem_data_store_page_fault_i;
                wb_data_load_page_fault_o <= mem_data_load_page_fault_i;
                wb_data_page_fault_addr_o <= mem_data_page_fault_addr_i;
                wb_address_misaligned_o <= mem_address_misaligned_i;
            end else if (wb_ready_i) begin
                wb_valid_o <= '0;
            end
        end
    end

    `ifdef FORMAL
    // Why: writeback is the retirement boundary, so a MEM result held behind
    // a WB stall must not turn into a different register write or fault.
    // What: a flush inserts a bubble; otherwise a valid WB entry keeps its PC,
    // control, result, and every recorded memory/alignment fault until WB
    // accepts it.  How: when $past(wb_ready_i) is low, compare each output to
    // its $past value.  mem_ready_o is not used because it describes whether
    // MEM can present a replacement, not whether WB consumed the current one.
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(wb_flush_i))
                assert (!wb_valid_o);
            if ($past(wb_valid_o) && !$past(wb_ready_i) && !$past(wb_flush_i)) begin
                assert (wb_valid_o);
                assert (wb_pc_o == $past(wb_pc_o));
                assert (wb_pred_pc_o == $past(wb_pred_pc_o));
                assert (wb_ctrl_o == $past(wb_ctrl_o));
                assert (wb_rd_data_o == $past(wb_rd_data_o));
                assert (wb_data_mem_fault_o == $past(wb_data_mem_fault_o));
                assert (wb_data_store_page_fault_o == $past(wb_data_store_page_fault_o));
                assert (wb_data_load_page_fault_o == $past(wb_data_load_page_fault_o));
                assert (wb_address_misaligned_o == $past(wb_address_misaligned_o));
            end
        end
    end
    `endif
endmodule : mem_wb_reg
