import riscv::*;

module fetch (
    input logic clk,
    input logic rst_n,
    input logic            redirect_i,
    input logic [XLEN-1:0] redirect_pc_i,
    input logic [XLEN-1:0] if_pred_pc_i,
    input mem_res_t fetch_mem_res_i,
    input mem_req_t fetch_mem_req_i,
    input logic [XLEN-1:0] fetch_page_fault_addr_i,
    input logic     fetch_page_fault_i,
    input logic [XLEN-1:0]   fetch_mem_fault_addr_i,
    input mem_fault_t        fetch_mem_fault_i,
    input logic if_ready,
    output logic [XLEN-1:0] fetch_pc_o,
    output logic [XLEN-1:0] inst_pc_o,
    output logic [XLEN-1:0] inst_pred_pc_o,
    output logic [IALIGN-1:0] inst_o,
    output logic              if_valid_o,
    output mem_fault_t        inst_mem_fault_q,
    output logic [XLEN-1:0]   inst_mem_fault_addr_q,
    output logic              inst_page_fault_q,
    output logic [XLEN-1:0]   inst_page_fault_addr_q
);
    logic fetch_result_valid;

    // This is asserted when a fetch has completed in some way. A fetch can either complete with an
    // instruction from memory, or some kind of access fault.
    assign fetch_result_valid = (fetch_mem_req_i.op == MFETCH && fetch_mem_res_i.valid)
                                || fetch_page_fault_i
                                || (fetch_mem_fault_i != FAULT_NONE);
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            fetch_pc_o <= RESET_PC;
            inst_pc_o <= RESET_PC;
            inst_pred_pc_o <= RESET_PC;
            inst_o <= RISCV_NOP;
            if_valid_o <= '0;
            inst_page_fault_q <= '0;
            inst_page_fault_addr_q <= RESET_PC;
            inst_mem_fault_q <= FAULT_NONE;
            inst_mem_fault_addr_q <= RESET_PC;
        // A redirect always restarts fetching at its target, whether or not the
        // instruction buffer currently holds a valid instruction.
        end else if (redirect_i) begin
            // The buffered instruction resolved to a different successor than the
            // sequential/predicted fetch address. Discard that fetch and restart.
            if_valid_o <= 1'b0;
            fetch_pc_o <= redirect_pc_i;
            inst_pred_pc_o <= redirect_pc_i;
            inst_page_fault_q <= 1'b0;
            inst_mem_fault_q <= FAULT_NONE;
        // Accept a completed fetch when the instruction buffer has capacity (including
        // initial boot), or when its current instruction retires this cycle and can
        // be atomically replaced. When the buffer holds an unretired instruction,
        // retain it and do not overwrite its instruction, PC, or fault metadata.
        end else if (fetch_result_valid && (!if_valid_o || if_ready)) begin
            // The result belongs to the request at fetch_pc_o.
            inst_o <= fetch_mem_res_i.data[31:0];
            inst_pc_o <= fetch_pc_o;
            inst_pred_pc_o <= if_pred_pc_i;
            if_valid_o <= 1'b1;

            inst_page_fault_q <= fetch_page_fault_i;
            inst_page_fault_addr_q <= fetch_page_fault_addr_i;
            inst_mem_fault_q <= fetch_mem_fault_i;
            inst_mem_fault_addr_q <= fetch_mem_fault_addr_i;

            fetch_pc_o <= if_pred_pc_i;

        end else if (if_ready) begin
            // Current instruction retired without a replacement response.
            if_valid_o <= 1'b0;
            inst_page_fault_q <= 1'b0;
            inst_mem_fault_q <= FAULT_NONE;
        end
    end
endmodule
