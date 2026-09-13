import riscv::*;

module fetch (
    input logic clk,
    input logic rst_n,
    input logic [XLEN-1:0] next_pc_i,
    input mem_res_t fetch_mem_res_i,
    input mem_req_t fetch_mem_req_i,
    input logic [XLEN-1:0] fetch_page_fault_addr_i,
    input logic     fetch_page_fault_i,
    input logic [XLEN-1:0]   fetch_mem_fault_addr_i,
    input mem_fault_t        fetch_mem_fault_i,
    input logic commit_i,
    output logic [XLEN-1:0] fetch_pc_o,
    output logic [XLEN-1:0] inst_pc_o,
    output logic [IALIGN-1:0] inst_o,
    output logic              inst_valid_o,
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
            inst_o <= RISCV_NOP;
            inst_valid_o <= '0;
            inst_page_fault_q <= '0;
            inst_page_fault_addr_q <= RESET_PC;
            inst_mem_fault_q <= FAULT_NONE;
            inst_mem_fault_addr_q <= RESET_PC;
        // If the current instruction is valid, and the next instruction is wrong, we want to change
        // which instruction we're fetching.
        // This is necessary because, at reset, inst_valid_o = 0, fetch_pc_o = 0, next_pc_i = 4,
        // which would result in skipping pc = 0 if inst_valid_o is not required.
        end else if (inst_valid_o && fetch_pc_o != next_pc_i) begin
            // The buffered instruction resolved to a different successor than the
            // sequential/predicted fetch address. Discard that fetch and restart.
            inst_valid_o <= 1'b0;
            fetch_pc_o <= next_pc_i;
            inst_page_fault_q <= 1'b0;
            inst_mem_fault_q <= FAULT_NONE;
        // Accept a completed fetch when the instruction buffer has capacity (including
        // initial boot), or when its current instruction retires this cycle and can
        // be atomically replaced. When the buffer holds an unretired instruction,
        // retain it and do not overwrite its instruction, PC, or fault metadata.
        end else if (fetch_result_valid && (!inst_valid_o || commit_i)) begin
            // The result belongs to the request at fetch_pc_o.
            inst_o <= fetch_mem_res_i.data[31:0];
            inst_pc_o <= fetch_pc_o;
            inst_valid_o <= 1'b1;

            inst_page_fault_q <= fetch_page_fault_i;
            inst_page_fault_addr_q <= fetch_page_fault_addr_i;
            inst_mem_fault_q <= fetch_mem_fault_i;
            inst_mem_fault_addr_q <= fetch_mem_fault_addr_i;

            // Default sequential prediction.
            fetch_pc_o <= fetch_pc_o + PC_INC;

        end else if (commit_i) begin
            // Current instruction retired without a replacement response.
            inst_valid_o <= 1'b0;
            inst_page_fault_q <= 1'b0;
            inst_mem_fault_q <= FAULT_NONE;
        end
    end
endmodule
