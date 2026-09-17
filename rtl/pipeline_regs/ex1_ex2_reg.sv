import riscv::*;
import imul_pkg::*;

// Pipeline control logic is commented more completely in if_id_reg.sv. The control logic is the
// same between all pipeline registers.

module ex1_ex2_reg (
    input logic              clk,
    input logic              rst_n,

    input logic              stall_i,
    input logic              ex2_flush_i,
    output logic             ex1_flush_o,

    // Upstream interface (execute 1)
    input logic                         ex1_valid_i,
    output logic                        ex1_ready_o,
    input logic [XLEN-1:0]              ex1_pc_i,
    input logic [XLEN-1:0]              ex1_pred_pc_i,
    input ctrl_t                        ex1_ctrl_i,
    input sfence_sel_t                  ex1_sfence_sel_i,
    input logic [XLEN-1:0]              ex1_addr_i,
    input logic [XLEN-1:0]              ex1_store_data_i,
    input logic [XLEN-1:0]              ex1_rd_data_i,
    input logic [XLEN-1:0]              ex1_csr_data_write_i,
    input logic [XLEN-1:0]              ex1_csr_operand_i,
    input mem_fault_t                   ex1_fetch_mem_fault_i,
    input logic [XLEN-1:0]              ex1_fetch_mem_fault_addr_i,
    input logic                         ex1_fetch_page_fault_i,
    input logic [XLEN-1:0]              ex1_fetch_page_fault_addr_i,
    input logic                         ex1_address_misaligned_i,
    input logic [MAX_HEIGHT[0]-1:0]     ex1_imul_intermediate_i [PP_WIDTH-1:0],

    // Downstream interface (execute 2)
    input logic                         ex2_ready_i,
    output logic                        ex2_valid_o,
    output logic [XLEN-1:0]             ex2_pc_o,
    output logic [XLEN-1:0]             ex2_pred_pc_o,
    output ctrl_t                       ex2_ctrl_o,
    output sfence_sel_t                 ex2_sfence_sel_o,
    output logic [XLEN-1:0]             ex2_addr_o,
    output logic [XLEN-1:0]             ex2_store_data_o,
    output logic [XLEN-1:0]             ex2_rd_data_o,
    output logic [XLEN-1:0]             ex2_csr_data_write_o,
    output logic [XLEN-1:0]             ex2_csr_operand_o,
    output mem_fault_t                  ex2_fetch_mem_fault_o,
    output logic [XLEN-1:0]             ex2_fetch_mem_fault_addr_o,
    output logic                        ex2_fetch_page_fault_o,
    output logic [XLEN-1:0]             ex2_fetch_page_fault_addr_o,
    output logic                        ex2_address_misaligned_o,
    output logic [MAX_HEIGHT[0]-1:0]    ex2_imul_intermediate_o [PP_WIDTH-1:0]
);
    assign ex1_flush_o = ex2_flush_i;
    assign ex1_ready_o = (ex2_ready_i || !ex2_valid_o) && !stall_i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex2_valid_o <= '0;
            ex2_pc_o <= RESET_PC;
            ex2_pred_pc_o <= RESET_PC;
            ex2_ctrl_o <= '0;
            ex2_sfence_sel_o <= '0;
            ex2_addr_o <= '0;
            ex2_store_data_o <= '0;
            ex2_rd_data_o <= '0;
            ex2_csr_data_write_o <= '0;
            ex2_csr_operand_o <= '0;
            ex2_fetch_mem_fault_o <= FAULT_NONE;
            ex2_fetch_mem_fault_addr_o <= RESET_PC;
            ex2_fetch_page_fault_o <= '0;
            ex2_fetch_page_fault_addr_o <= RESET_PC;
            ex2_address_misaligned_o <= '0;
            for (int column = 0; column < PP_WIDTH; column++) begin
                ex2_imul_intermediate_o[column] <= '0;
            end
        end else if (ex2_flush_i) begin
            ex2_valid_o <= '0;
        end else begin
            if (ex1_ready_o && ex1_valid_i) begin
                ex2_valid_o <= '1;
                ex2_pc_o <= ex1_pc_i;
                ex2_pred_pc_o <= ex1_pred_pc_i;
                ex2_ctrl_o <= ex1_ctrl_i;
                ex2_sfence_sel_o <= ex1_sfence_sel_i;
                ex2_addr_o <= ex1_addr_i;
                ex2_store_data_o <= ex1_store_data_i;
                ex2_rd_data_o <= ex1_rd_data_i;
                ex2_csr_data_write_o <= ex1_csr_data_write_i;
                ex2_csr_operand_o <= ex1_csr_operand_i;
                ex2_fetch_mem_fault_o <= ex1_fetch_mem_fault_i;
                ex2_fetch_mem_fault_addr_o <= ex1_fetch_mem_fault_addr_i;
                ex2_fetch_page_fault_o <= ex1_fetch_page_fault_i;
                ex2_fetch_page_fault_addr_o <= ex1_fetch_page_fault_addr_i;
                ex2_address_misaligned_o <= ex1_address_misaligned_i;
                ex2_imul_intermediate_o <= ex1_imul_intermediate_i;
            end else if (ex2_ready_i) begin
                ex2_valid_o <= '0;
            end
        end
    end

    `ifdef FORMAL
    // Why: EX2 must receive a coherent EX1 result after a stall; mixing an
    // address/control field from one instruction with data from another is
    // especially dangerous for loads and stores.  What: a flush clears valid,
    // and an unaccepted valid EX2 entry keeps its PC, control, address, data,
    // and fetch-fault fields.  How: when $past(ex2_ready_i) is low, compare
    // each current output to its $past value; ex1_ready_o is only the upstream
    // replacement handshake and is deliberately not used as the hold test.
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(ex2_flush_i))
                assert (!ex2_valid_o);
            if ($past(ex2_valid_o) && !$past(ex2_ready_i) && !$past(ex2_flush_i)) begin
                assert (ex2_valid_o);
                assert (ex2_pc_o == $past(ex2_pc_o));
                assert (ex2_pred_pc_o == $past(ex2_pred_pc_o));
                assert (ex2_ctrl_o == $past(ex2_ctrl_o));
                assert (ex2_addr_o == $past(ex2_addr_o));
                assert (ex2_store_data_o == $past(ex2_store_data_o));
                assert (ex2_rd_data_o == $past(ex2_rd_data_o));
                assert (ex2_fetch_mem_fault_o == $past(ex2_fetch_mem_fault_o));
                assert (ex2_fetch_page_fault_o == $past(ex2_fetch_page_fault_o));
            end
        end
    end
    `endif
endmodule : ex1_ex2_reg
