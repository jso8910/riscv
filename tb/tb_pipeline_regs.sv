`timescale 1ns/1ps
import riscv::*;
import imul_pkg::*;

module tb_pipeline_regs;
    logic clk, rst_n;
    logic if_valid, id_valid, ex1_valid, ex2_valid, ex3_valid, mem_valid;
    logic if_ready, id_ready, ex1_ready, ex2_ready, ex3_ready, mem_ready, wb_ready;
    logic if_stall, id_stall, ex1_stall, ex2_stall, ex3_stall, mem_stall;
    logic if_flush, id_flush, ex1_flush, ex2_flush, ex3_flush, mem_flush;
    logic id_valid_o, ex1_valid_o, ex2_valid_o, ex3_valid_o, mem_valid_o, wb_valid_o;
    logic if_backflush, id_backflush, ex1_backflush, ex2_backflush, ex3_backflush, mem_backflush;
    logic [XLEN-1:0] pc = 64'h40;
    logic [IALIGN-1:0] inst = 32'h13;
    ctrl_t ctrl;
    sfence_sel_t sfence_sel;
    mem_res_t mem_res;
    logic [MAX_HEIGHT[1]-1:0] ex1_imul_intermediate [PP_WIDTH-1:0];
    logic [MAX_HEIGHT[5]-1:0] ex2_imul_intermediate [PP_WIDTH-1:0];
    int tests_run, tests_failed;

    if_id_reg if_id (
        .clk, .rst_n, .stall_i(if_stall), .id_flush_i(if_flush), .if_flush_o(if_backflush),
        .if_valid_i(if_valid), .if_ready_o(if_ready), .if_pc_i(pc), .if_pred_pc_i(pc + PC_INC),
        .if_inst_i(inst), .if_fetch_mem_fault_i(FAULT_NONE), .if_fetch_mem_fault_addr_i('0),
        .if_fetch_page_fault_i(1'b0), .if_fetch_page_fault_addr_i('0), .id_ready_i(id_ready),
        .id_valid_o(id_valid_o), .id_pc_o(), .id_pred_pc_o(), .id_inst_o(), .id_fetch_mem_fault_o(),
        .id_fetch_mem_fault_addr_o(), .id_fetch_page_fault_o(), .id_fetch_page_fault_addr_o()
    );
    id_ex1_reg id_ex1 (
        .clk, .rst_n, .stall_i(id_stall), .ex1_flush_i(id_flush), .id_flush_o(id_backflush),
        .id_valid_i(id_valid), .id_ready_o(id_ready), .id_pc_i(pc), .id_pred_pc_i(pc + PC_INC),
        .id_ctrl_i(ctrl), .id_rs1_data_raw_i('0), .id_rs2_data_raw_i('0), .id_csr_data_read_raw_i('0),
        .id_imm_i('0), .id_fetch_mem_fault_i(FAULT_NONE), .id_fetch_mem_fault_addr_i('0),
        .id_fetch_page_fault_i(1'b0), .id_fetch_page_fault_addr_i('0), .ex1_ready_i(ex1_ready),
        .ex1_valid_o(ex1_valid_o), .ex1_pc_o(), .ex1_pred_pc_o(), .ex1_ctrl_o(), .ex1_rs1_data_raw_o(),
        .ex1_rs2_data_raw_o(), .ex1_csr_data_read_raw_o(), .ex1_imm_o(), .ex1_fetch_mem_fault_o(),
        .ex1_fetch_mem_fault_addr_o(), .ex1_fetch_page_fault_o(), .ex1_fetch_page_fault_addr_o()
    );
    ex1_ex2_reg ex1_ex2 (
        .clk, .rst_n, .stall_i(ex1_stall), .ex2_flush_i(ex1_flush), .ex1_flush_o(ex1_backflush),
        .ex1_valid_i(ex1_valid), .ex1_ready_o(ex1_ready), .ex1_pc_i(pc), .ex1_pred_pc_i(pc + PC_INC),
        .ex1_ctrl_i(ctrl), .ex1_sfence_sel_i(sfence_sel), .ex1_addr_i('0), .ex1_store_data_i('0),
        .ex1_rd_data_i('0), .ex1_csr_data_write_i('0), .ex1_csr_operand_i('0), .ex1_fetch_mem_fault_i(FAULT_NONE),
        .ex1_fetch_mem_fault_addr_i('0), .ex1_fetch_page_fault_i(1'b0), .ex1_fetch_page_fault_addr_i('0),
        .ex1_address_misaligned_i(1'b0), .ex1_imul_intermediate_i(ex1_imul_intermediate),
        .ex2_ready_i(ex2_ready), .ex2_valid_o(ex2_valid_o), .ex2_pc_o(), .ex2_pred_pc_o(), .ex2_ctrl_o(),
        .ex2_sfence_sel_o(), .ex2_addr_o(), .ex2_store_data_o(), .ex2_rd_data_o(), .ex2_csr_data_write_o(),
        .ex2_csr_operand_o(), .ex2_fetch_mem_fault_o(), .ex2_fetch_mem_fault_addr_o(), .ex2_fetch_page_fault_o(),
        .ex2_fetch_page_fault_addr_o(), .ex2_address_misaligned_o(), .ex2_imul_intermediate_o()
    );
    ex2_ex3_reg ex2_ex3 (
        .clk, .rst_n, .stall_i(ex2_stall), .ex3_flush_i(ex2_flush), .ex2_flush_o(ex2_backflush),
        .ex2_valid_i(ex2_valid), .ex2_ready_o(ex2_ready), .ex2_pc_i(pc), .ex2_pred_pc_i(pc + PC_INC),
        .ex2_ctrl_i(ctrl), .ex2_sfence_sel_i(sfence_sel), .ex2_addr_i('0), .ex2_store_data_i('0),
        .ex2_rd_data_i('0), .ex2_csr_data_write_i('0), .ex2_csr_operand_i('0), .ex2_fetch_mem_fault_i(FAULT_NONE),
        .ex2_fetch_mem_fault_addr_i('0), .ex2_fetch_page_fault_i(1'b0), .ex2_fetch_page_fault_addr_i('0),
        .ex2_address_misaligned_i(1'b0), .ex2_imul_intermediate_i(ex2_imul_intermediate),
        .ex3_ready_i(ex3_ready), .ex3_valid_o(ex3_valid_o), .ex3_pc_o(), .ex3_pred_pc_o(), .ex3_ctrl_o(),
        .ex3_sfence_sel_o(), .ex3_addr_o(), .ex3_store_data_o(), .ex3_rd_data_o(), .ex3_csr_data_write_o(),
        .ex3_csr_operand_o(), .ex3_fetch_mem_fault_o(), .ex3_fetch_mem_fault_addr_o(), .ex3_fetch_page_fault_o(),
        .ex3_fetch_page_fault_addr_o(), .ex3_address_misaligned_o(), .ex3_imul_intermediate_o()
    );
    ex3_mem_reg ex3_mem (
        .clk, .rst_n, .stall_i(ex3_stall), .mem_flush_i(ex3_flush), .ex3_flush_o(ex3_backflush),
        .ex3_valid_i(ex3_valid), .ex3_ready_o(ex3_ready), .ex3_pc_i(pc), .ex3_pred_pc_i(pc + PC_INC),
        .ex3_ctrl_i(ctrl), .ex3_sfence_sel_i(sfence_sel), .ex3_addr_i('0), .ex3_store_data_i('0),
        .ex3_rd_data_i('0), .ex3_csr_data_write_i('0), .ex3_csr_operand_i('0), .ex3_fetch_mem_fault_i(FAULT_NONE),
        .ex3_fetch_mem_fault_addr_i('0), .ex3_fetch_page_fault_i(1'b0), .ex3_fetch_page_fault_addr_i('0),
        .ex3_address_misaligned_i(1'b0), .mem_ready_i(mem_ready), .mem_valid_o(mem_valid_o),
        .mem_pc_o(), .mem_pred_pc_o(), .mem_ctrl_o(), .mem_sfence_sel_o(), .mem_addr_o(),
        .mem_store_data_o(), .mem_rd_data_o(), .mem_csr_data_write_o(), .mem_csr_operand_o(), .mem_fetch_mem_fault_o(),
        .mem_fetch_mem_fault_addr_o(), .mem_fetch_page_fault_o(), .mem_fetch_page_fault_addr_o(),
        .mem_address_misaligned_o()
    );
    mem_wb_reg mem_wb (
        .clk, .rst_n, .stall_i(mem_stall), .wb_flush_i(mem_flush), .mem_flush_o(mem_backflush),
        .mem_data_res_i(mem_res), .mem_valid_i(mem_valid), .mem_ready_o(mem_ready), .mem_pc_i(pc),
        .mem_pred_pc_i(pc + PC_INC), .mem_ctrl_i(ctrl), .mem_sfence_sel_i(sfence_sel), .mem_rd_data_i('0),
        .mem_csr_data_write_i('0), .mem_csr_operand_i('0), .mem_fetch_mem_fault_i(FAULT_NONE), .mem_fetch_mem_fault_addr_i('0),
        .mem_fetch_page_fault_i(1'b0), .mem_fetch_page_fault_addr_i('0), .mem_data_mem_fault_i(FAULT_NONE),
        .mem_data_mem_fault_addr_i('0), .mem_data_store_page_fault_i(1'b0), .mem_data_load_page_fault_i(1'b0),
        .mem_data_page_fault_addr_i('0), .mem_address_misaligned_i(1'b0), .wb_valid_o(wb_valid_o),
        .wb_ready_i(wb_ready), .wb_pc_o(), .wb_pred_pc_o(), .wb_ctrl_o(), .wb_sfence_sel_o(),
        .wb_rd_data_o(), .wb_csr_data_write_o(), .wb_csr_operand_o(), .wb_fetch_mem_fault_o(), .wb_fetch_mem_fault_addr_o(),
        .wb_fetch_page_fault_o(), .wb_fetch_page_fault_addr_o(), .wb_data_mem_fault_o(),
        .wb_data_mem_fault_addr_o(), .wb_data_store_page_fault_o(), .wb_data_load_page_fault_o(),
        .wb_data_page_fault_addr_o(), .wb_address_misaligned_o()
    );
    always #5 clk = ~clk;
    task automatic check(input string name, input logic condition);
        begin tests_run++; if (!condition) begin tests_failed++; $fatal(1, "%s", name); end end
    endtask
    task automatic tick; begin @(posedge clk); #1; end endtask
    initial begin
        clk = 0; rst_n = 0; ctrl = '0; sfence_sel = '0; mem_res = '0;
        if_valid = 0; id_valid = 0; ex1_valid = 0; ex2_valid = 0; ex3_valid = 0; mem_valid = 0;
        if_stall = 0; id_stall = 0; ex1_stall = 0; ex2_stall = 0; ex3_stall = 0; mem_stall = 0;
        if_flush = 0; id_flush = 0; ex1_flush = 0; ex2_flush = 0; ex3_flush = 0; mem_flush = 0; wb_ready = 1;
        tests_run = 0; tests_failed = 0; tick();
        check("reset clears every pipeline valid", !id_valid_o && !ex1_valid_o && !ex2_valid_o && !ex3_valid_o && !mem_valid_o && !wb_valid_o);
        rst_n = 1; if_valid = 1; id_valid = 1; ex1_valid = 1; ex2_valid = 1; ex3_valid = 1; mem_valid = 1; tick();
        check("each register captures a valid transaction", id_valid_o && ex1_valid_o && ex2_valid_o && ex3_valid_o && mem_valid_o && wb_valid_o);
        if_flush = 1; id_flush = 1; ex1_flush = 1; ex2_flush = 1; ex3_flush = 1; mem_flush = 1; #1;
        check("flush signals propagate backwards", if_backflush && id_backflush && ex1_backflush && ex2_backflush && ex3_backflush && mem_backflush);
        tick();
        check("flush clears every pipeline valid", !id_valid_o && !ex1_valid_o && !ex2_valid_o && !ex3_valid_o && !mem_valid_o && !wb_valid_o);
        if_flush = 0; id_flush = 0; ex1_flush = 0; ex2_flush = 0; ex3_flush = 0; mem_flush = 0;
        if_stall = 1; id_stall = 1; ex1_stall = 1; ex2_stall = 1; ex3_stall = 1; mem_stall = 1;
        #1; check("stall deasserts every upstream ready", !if_ready && !id_ready && !ex1_ready && !ex2_ready && !ex3_ready && !mem_ready);
        $display("tb_pipeline_regs: all %0d checks passed", tests_run); $finish;
    end
endmodule
