`timescale 1ns/1ps
import riscv::*;

module tb_pipeline_regs;
    logic clk, rst_n;
    logic if_valid, id_valid, ex_valid, mem_valid;
    logic if_ready, id_ready, ex_ready, mem_ready, wb_ready;
    logic if_stall, id_stall, ex_stall, mem_stall;
    logic if_flush, id_flush, ex_flush, mem_flush;
    logic id_valid_o, ex_valid_o, mem_valid_o, wb_valid_o;
    logic if_backflush, id_backflush, ex_backflush, mem_backflush;
    logic [XLEN-1:0] pc = 64'h40;
    logic [IALIGN-1:0] inst = 32'h13;
    ctrl_t ctrl;
    sfence_sel_t sfence_sel;
    mem_res_t mem_res;
    int tests_run, tests_failed;

    if_id_reg if_id (
        .clk, .rst_n, .stall_i(if_stall), .id_flush_i(if_flush), .if_flush_o(if_backflush),
        .if_valid_i(if_valid), .if_ready_o(if_ready), .if_pc_i(pc), .if_pred_pc_i(pc + PC_INC),
        .if_inst_i(inst), .if_fetch_mem_fault_i(FAULT_NONE), .if_fetch_mem_fault_addr_i('0),
        .if_fetch_page_fault_i(1'b0), .if_fetch_page_fault_addr_i('0), .id_ready_i(id_ready),
        .id_valid_o(id_valid_o), .id_pc_o(), .id_pred_pc_o(), .id_inst_o(), .id_fetch_mem_fault_o(),
        .id_fetch_mem_fault_addr_o(), .id_fetch_page_fault_o(), .id_fetch_page_fault_addr_o()
    );
    id_ex_reg id_ex (
        .clk, .rst_n, .stall_i(id_stall), .ex_flush_i(id_flush), .id_flush_o(id_backflush),
        .id_valid_i(id_valid), .id_ready_o(id_ready), .id_pc_i(pc), .id_pred_pc_i(pc + PC_INC),
        .id_ctrl_i(ctrl), .id_rs1_data_raw_i('0), .id_rs2_data_raw_i('0), .id_csr_data_read_raw_i('0),
        .id_imm_i('0), .id_fetch_mem_fault_i(FAULT_NONE), .id_fetch_mem_fault_addr_i('0),
        .id_fetch_page_fault_i(1'b0), .id_fetch_page_fault_addr_i('0), .ex_ready_i(ex_ready),
        .ex_valid_o(ex_valid_o), .ex_pc_o(), .ex_pred_pc_o(), .ex_ctrl_o(), .ex_rs1_data_raw_o(),
        .ex_rs2_data_raw_o(), .ex_csr_data_read_raw_o(), .ex_imm_o(), .ex_fetch_mem_fault_o(),
        .ex_fetch_mem_fault_addr_o(), .ex_fetch_page_fault_o(), .ex_fetch_page_fault_addr_o()
    );
    ex_mem_reg ex_mem (
        .clk, .rst_n, .stall_i(ex_stall), .mem_flush_i(ex_flush), .ex_flush_o(ex_backflush),
        .ex_valid_i(ex_valid), .ex_ready_o(ex_ready), .ex_pc_i(pc), .ex_pred_pc_i(pc + PC_INC),
        .ex_ctrl_i(ctrl), .ex_sfence_sel_i(sfence_sel), .ex_addr_i('0), .ex_store_data_i('0),
        .ex_rd_data_i('0), .ex_csr_data_write_i('0), .ex_csr_operand_i('0), .ex_fetch_mem_fault_i(FAULT_NONE),
        .ex_fetch_mem_fault_addr_i('0), .ex_fetch_page_fault_i(1'b0), .ex_fetch_page_fault_addr_i('0),
        .ex_address_misaligned_i(1'b0), .mem_ready_i(mem_ready), .mem_valid_o(mem_valid_o),
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
        if_valid = 0; id_valid = 0; ex_valid = 0; mem_valid = 0;
        if_stall = 0; id_stall = 0; ex_stall = 0; mem_stall = 0;
        if_flush = 0; id_flush = 0; ex_flush = 0; mem_flush = 0; wb_ready = 1;
        tests_run = 0; tests_failed = 0; tick();
        check("reset clears every pipeline valid", !id_valid_o && !ex_valid_o && !mem_valid_o && !wb_valid_o);
        rst_n = 1; if_valid = 1; id_valid = 1; ex_valid = 1; mem_valid = 1; tick();
        check("each register captures a valid transaction", id_valid_o && ex_valid_o && mem_valid_o && wb_valid_o);
        if_flush = 1; id_flush = 1; ex_flush = 1; mem_flush = 1; #1;
        check("flush signals propagate backwards", if_backflush && id_backflush && ex_backflush && mem_backflush);
        tick();
        check("flush clears every pipeline valid", !id_valid_o && !ex_valid_o && !mem_valid_o && !wb_valid_o);
        if_flush = 0; id_flush = 0; ex_flush = 0; mem_flush = 0; if_stall = 1; id_stall = 1; ex_stall = 1; mem_stall = 1;
        #1; check("stall deasserts every upstream ready", !if_ready && !id_ready && !ex_ready && !mem_ready);
        $display("tb_pipeline_regs: all %0d checks passed", tests_run); $finish;
    end
endmodule
