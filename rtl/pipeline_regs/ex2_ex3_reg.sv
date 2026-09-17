import riscv::*;
import imul_pkg::*;

// Pipeline control logic is commented more completely in if_id_reg.sv. The control logic is the
// same between all pipeline registers.

module ex2_ex3_reg (
    input logic              clk,
    input logic              rst_n,

    input logic              stall_i,
    input logic              ex3_flush_i,
    output logic             ex2_flush_o,

    // Upstream interface (execute 2)
    input logic                         ex2_valid_i,
    output logic                        ex2_ready_o,
    input logic [XLEN-1:0]              ex2_pc_i,
    input logic [XLEN-1:0]              ex2_pred_pc_i,
    input ctrl_t                        ex2_ctrl_i,
    input sfence_sel_t                  ex2_sfence_sel_i,
    input logic [XLEN-1:0]              ex2_addr_i,
    input logic [XLEN-1:0]              ex2_store_data_i,
    input logic [XLEN-1:0]              ex2_rd_data_i,
    input logic [XLEN-1:0]              ex2_csr_data_write_i,
    input logic [XLEN-1:0]              ex2_csr_operand_i,
    input mem_fault_t                   ex2_fetch_mem_fault_i,
    input logic [XLEN-1:0]              ex2_fetch_mem_fault_addr_i,
    input logic                         ex2_fetch_page_fault_i,
    input logic [XLEN-1:0]              ex2_fetch_page_fault_addr_i,
    input logic                         ex2_address_misaligned_i,
    input logic [MAX_HEIGHT[6]-1:0]     ex2_imul_intermediate_i [PP_WIDTH-1:0],

    // Downstream interface (execute 3)
    input logic                         ex3_ready_i,
    output logic                        ex3_valid_o,
    output logic [XLEN-1:0]             ex3_pc_o,
    output logic [XLEN-1:0]             ex3_pred_pc_o,
    output ctrl_t                       ex3_ctrl_o,
    output sfence_sel_t                 ex3_sfence_sel_o,
    output logic [XLEN-1:0]             ex3_addr_o,
    output logic [XLEN-1:0]             ex3_store_data_o,
    output logic [XLEN-1:0]             ex3_rd_data_o,
    output logic [XLEN-1:0]             ex3_csr_data_write_o,
    output logic [XLEN-1:0]             ex3_csr_operand_o,
    output mem_fault_t                  ex3_fetch_mem_fault_o,
    output logic [XLEN-1:0]             ex3_fetch_mem_fault_addr_o,
    output logic                        ex3_fetch_page_fault_o,
    output logic [XLEN-1:0]             ex3_fetch_page_fault_addr_o,
    output logic                        ex3_address_misaligned_o,
    output logic [MAX_HEIGHT[6]-1:0]    ex3_imul_intermediate_o [PP_WIDTH-1:0]
);
    assign ex2_flush_o = ex3_flush_i;
    assign ex2_ready_o = (ex3_ready_i || !ex3_valid_o) && !stall_i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex3_valid_o <= '0;
            ex3_pc_o <= RESET_PC;
            ex3_pred_pc_o <= RESET_PC;
            ex3_ctrl_o <= '0;
            ex3_sfence_sel_o <= '0;
            ex3_addr_o <= '0;
            ex3_store_data_o <= '0;
            ex3_rd_data_o <= '0;
            ex3_csr_data_write_o <= '0;
            ex3_csr_operand_o <= '0;
            ex3_fetch_mem_fault_o <= FAULT_NONE;
            ex3_fetch_mem_fault_addr_o <= RESET_PC;
            ex3_fetch_page_fault_o <= '0;
            ex3_fetch_page_fault_addr_o <= RESET_PC;
            ex3_address_misaligned_o <= '0;
            for (int column = 0; column < PP_WIDTH; column++) begin
                ex3_imul_intermediate_o[column] <= '0;
            end
        end else if (ex3_flush_i) begin
            ex3_valid_o <= '0;
        end else begin
            if (ex2_ready_o && ex2_valid_i) begin
                ex3_valid_o <= '1;
                ex3_pc_o <= ex2_pc_i;
                ex3_pred_pc_o <= ex2_pred_pc_i;
                ex3_ctrl_o <= ex2_ctrl_i;
                ex3_sfence_sel_o <= ex2_sfence_sel_i;
                ex3_addr_o <= ex2_addr_i;
                ex3_store_data_o <= ex2_store_data_i;
                ex3_rd_data_o <= ex2_rd_data_i;
                ex3_csr_data_write_o <= ex2_csr_data_write_i;
                ex3_csr_operand_o <= ex2_csr_operand_i;
                ex3_fetch_mem_fault_o <= ex2_fetch_mem_fault_i;
                ex3_fetch_mem_fault_addr_o <= ex2_fetch_mem_fault_addr_i;
                ex3_fetch_page_fault_o <= ex2_fetch_page_fault_i;
                ex3_fetch_page_fault_addr_o <= ex2_fetch_page_fault_addr_i;
                ex3_address_misaligned_o <= ex2_address_misaligned_i;
                ex3_imul_intermediate_o <= ex2_imul_intermediate_i;
            end else if (ex3_ready_i) begin
                ex3_valid_o <= '0;
            end
        end
    end

    `ifdef FORMAL
    // Why: EX3 must see one complete instruction when it stalls, not a blend
    // of two EX2 results.  What: flushes produce bubbles, and a valid EX3
    // entry retains its PC, control, address, store data, result, and fault
    // metadata until EX3 accepts it.  How: a low $past(ex3_ready_i) means the
    // downstream consumer did not accept the entry, so every listed output is
    // compared against its prior sampled value.
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(ex3_flush_i))
                assert (!ex3_valid_o);
            if ($past(ex3_valid_o) && !$past(ex3_ready_i) && !$past(ex3_flush_i)) begin
                assert (ex3_valid_o);
                assert (ex3_pc_o == $past(ex3_pc_o));
                assert (ex3_pred_pc_o == $past(ex3_pred_pc_o));
                assert (ex3_ctrl_o == $past(ex3_ctrl_o));
                assert (ex3_addr_o == $past(ex3_addr_o));
                assert (ex3_store_data_o == $past(ex3_store_data_o));
                assert (ex3_rd_data_o == $past(ex3_rd_data_o));
                assert (ex3_fetch_mem_fault_o == $past(ex3_fetch_mem_fault_o));
                assert (ex3_fetch_page_fault_o == $past(ex3_fetch_page_fault_o));
            end
        end
    end
    `endif
endmodule : ex2_ex3_reg
