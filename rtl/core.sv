import riscv::*;

module riscv_core (
    input logic                 clk,
    input logic                 rst_n,
    input logic [IALIGN-1:0]    inst_i,
    input logic [WWIDTH-1:0]    data_mem_data_i,

    output logic [XLEN-1:0]     pc_o,
    output logic [WWIDTH/8-1:0] data_mem_we_o,
    output logic [XLEN-1:0]     data_mem_addr_o,
    output logic [WWIDTH-1:0]   data_mem_data_o,
    output ctrl_t               ctrl_o
);
    // ================
    // Wire definitions
    // ================
    ctrl_t ctrl;
    logic [XLEN-1:0] next_pc, rs1_data, rs2_data;
    logic [XLEN-1:0] alu_res, imm, mem_content, op1;

    // ===========
    // Assignments
    // ===========
    assign ctrl_o = ctrl;
    assign data_mem_addr_o = alu_res;
    assign data_mem_data_o = rs2_data;

    // =====================
    // =====================
    // Module instantiations
    // =====================
    // =====================

    // =====
    // Fetch
    // =====
    fetch u_fetch (
        .clk          (clk),
        .rst_n        (rst_n),
        .next_pc_i    (next_pc),
        .pc_o         (pc_o)
    );

    next_pc_unit u_next_pc_unit (
        .ctrl_i        (ctrl),
        .pc_i          (pc_o),
        .rs1_data_i    (rs1_data),
        .rs2_data_i    (rs2_data),
        .alu_res_i     (alu_res),
        .next_pc_o     (next_pc)
    );

    // ==============
    // Decode/control
    // ==============
    control_unit u_control_unit (
        .inst_i    (inst_i),
        .imm_o     (imm),
        .ctrl_o    (ctrl)
    );

    // =============
    // Operand 1 mux
    // =============
    always_comb begin
        case (ctrl.op1_src)
            RS1 : op1 = rs1_data;
            PC : op1 = pc_o;
        endcase
    end

    // =======
    // Execute
    // =======
    alu u_alu (
        .ctrl_i        (ctrl),
        .op1_data_i    (op1),
        .op2_data_i    (rs2_data),
        .imm_i         (imm),
        .res_o         (alu_res)
    );

    // =======================
    // Register file/writeback
    // =======================
    regfile u_regfile (
        .clk           (clk),
        .rst_n         (rst_n),
        .ctrl_i        (ctrl),
        .alu_i         (alu_res),
        .mem_i         (mem_content),
        .pc_i          (pc_o),
        .imm_i         (imm),
        .rs1_data_o    (rs1_data),
        .rs2_data_o    (rs2_data)
    );

    // =================
    // Memory controller
    // =================
    memory_controller u_memory_controller (
        .data_i    (data_mem_data_i),
        .ctrl_i    (ctrl),
        .data_o    (mem_content),
        .we_o      (data_mem_we_o)
    );
endmodule

module riscv_system #(
    parameter logic [XLEN-1:0] IMEM_START_ADDRESS_P = IMEM_START_ADDRESS,
    parameter logic [XLEN-1:0] IMEM_END_ADDRESS_P   = IMEM_END_ADDRESS,
    parameter logic [XLEN-1:0] DMEM_START_ADDRESS_P = DMEM_START_ADDRESS,
    parameter logic [XLEN-1:0] DMEM_END_ADDRESS_P   = DMEM_END_ADDRESS
)(
    input logic clk,
    input logic rst_n
);
    // Wire instantiations (_i and _o suffixes from perspective of riscv_core)
    logic [IALIGN-1:0] inst_i;
    logic [WWIDTH-1:0] data_mem_data_i, data_mem_data_o;
    logic [XLEN-1:0] pc_o, data_mem_addr_o;
    logic [WWIDTH/8-1:0] data_mem_we_o;
    ctrl_t ctrl_o;

    // CPU core
    riscv_core u_riscv_core (
        .clk                (clk),
        .rst_n              (rst_n),
        .inst_i             (inst_i),
        .data_mem_data_i    (data_mem_data_i),
        .pc_o               (pc_o),
        .data_mem_we_o      (data_mem_we_o),
        .data_mem_addr_o    (data_mem_addr_o),
        .data_mem_data_o    (data_mem_data_o),
        .ctrl_o             (ctrl_o)
    );

    // Instruction memory
    sram #(
        .DWIDTH           (IALIGN),
        .NUM_BYTES        (IALIGN/8),
        .AWIDTH           (XLEN),
        .START_ADDRESS    (IMEM_START_ADDRESS_P),
        .END_ADDRESS      (IMEM_END_ADDRESS_P)
    ) instruction_sram (
        .clk              (clk),
        .address_i        (pc_o),
        .data_i           (32'b0),
        .we_i             ('0),
        .data_o           (inst_i)
    );

    // Data memory
    sram #(
        .DWIDTH           (WWIDTH),
        .NUM_BYTES        (WWIDTH/8),
        .AWIDTH           (XLEN),
        .START_ADDRESS    (DMEM_START_ADDRESS_P),
        .END_ADDRESS      (DMEM_END_ADDRESS_P)
    ) data_sram (
        .clk              (clk),
        .address_i        (data_mem_addr_o),
        .data_i           (data_mem_data_o),
        .we_i             (data_mem_we_o),
        .data_o           (data_mem_data_i)
    );
endmodule
