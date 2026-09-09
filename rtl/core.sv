import riscv::*;

module riscv_core (
    input logic                 clk,
    input logic                 rst_n,
    input logic [IALIGN-1:0]    inst_i,
    input logic [WWIDTH-1:0]    data_mem_data_i,

    output logic [XLEN-1:0]     pc_o,
    output logic [WWIDTH/8-1:0] data_mem_we_o,
    output logic [XLEN-1:0]     data_mem_addr_o,
    output logic [WWIDTH-1:0]   data_mem_data_o
);
    // ================
    // Wire definitions
    // ================
    ctrl_t ctrl;
    trap_t trap;
    machine_privilege_t machine_privilege;
    logic [XLEN-1:0] next_pc, rs1_data, rs2_data, csr_val,
                     alu_res, imm, mem_content, op1, mepc, mtvec,
                     pma_faulting_addr, pmp_faulting_addr, mstatus;
    logic csr_illegal_inst, commit, retire_count, cycle_tick, address_misaligned,
          pma_instruction_fetch_exception, pma_write_exception, pma_read_exception,
          memory_checker_hardware_fault, hardware_fault, pmp_write_exception, pmp_read_exception,
          pmp_instruction_fetch_exception;

    logic [7:0]      pmp_cfg [0:63];
    logic [XLEN-1:0] pmp_addr [0:63];

    // ===========
    // Assignments
    // ===========
    assign data_mem_addr_o = alu_res;
    assign data_mem_data_o = rs2_data;
    // suppress side effects on trap
    assign commit = ~trap.is_trap;
    assign cycle_tick = '1;
    assign retire_count = commit;

    // hardware fault logic (bitwise OR :P)
    assign hardware_fault = memory_checker_hardware_fault;

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
        .mepc_i        (mepc),
        .mtvec_i       (mtvec),
        .trap_i        (trap),
        .next_pc_o     (next_pc),
        .address_misaligned_o (address_misaligned)
    );

    // ==============
    // Decode/control
    // ==============
    control_unit u_control_unit (
        .inst_i    (inst_i),
        .current_privilege_i(machine_privilege),
        .imm_o     (imm),
        .ctrl_o    (ctrl)
    );

    // ===============
    // Trap controller
    // ===============
    trap_controller u_trap_controller (
        .ctrl_i              (ctrl),
        .hardware_fault_i    (hardware_fault),
        .csr_illegal_inst_i  (csr_illegal_inst),
        .address_misaligned_i(address_misaligned),

        .pma_instruction_fetch_exception_i(pma_instruction_fetch_exception),
        .pma_write_exception_i(pma_write_exception),
        .pma_read_exception_i(pma_read_exception),
        .pma_faulting_addr_i (pma_faulting_addr),

        .pmp_instruction_fetch_exception_i(pmp_instruction_fetch_exception),
        .pmp_read_exception_i(pmp_read_exception),
        .pmp_write_exception_i(pmp_write_exception),
        .pmp_faulting_addr_i(pmp_faulting_addr),

        .current_privilege_i (machine_privilege),
        .pc_i                (pc_o),
        .trap_o              (trap)
    );

    // =============
    // Operand 1 mux
    // =============
    always_comb begin
        case (ctrl.op1_src)
            RS1 : op1 = rs1_data;
            PC : op1 = pc_o;
            default: $fatal(1);
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
        .commit_i      (commit),
        .alu_i         (alu_res),
        .mem_i         (mem_content),
        .pc_i          (pc_o),
        .csr_i         (csr_val),
        .imm_i         (imm),
        .rs1_data_o    (rs1_data),
        .rs2_data_o    (rs2_data)
    );

    // ========
    // CSR file
    // ========
    csrfile u_csrfile (
        .clk                (clk),
        .rst_n              (rst_n),
        .ctrl_i             (ctrl),
        .cycle_tick_i       (cycle_tick),
        .retire_count_i     (retire_count),
        .rs1_i              (rs1_data),
        .trap_i             (trap),
        .csr_val_o          (csr_val),
        .mepc_o             (mepc),
        .mtvec_o            (mtvec),
        .mstatus_o          (mstatus),
        .pmp_cfg_o          (pmp_cfg),
        .pmp_addr_o         (pmp_addr),
        .csr_illegal_inst_o (csr_illegal_inst),
        .machine_privilege_o(machine_privilege)
    );

    // =================
    // Memory controller
    // =================
    memory_controller u_memory_controller (
        .data_i    (data_mem_data_i),
        .ctrl_i    (ctrl),
        .commit_i  (commit),
        .data_o    (mem_content),
        .we_o      (data_mem_we_o)
    );

    physical_memory_checker u_physical_memory_checker (
        .current_privilege_i              (machine_privilege),
        .pmp_cfg_i                        (pmp_cfg),
        .pmp_addr_i                       (pmp_addr),
        .pc_i                             (pc_o),
        .ctrl_i                           (ctrl),
        .data_mem_addr_i                  (data_mem_addr_o),
        .mstatus_i                        (mstatus),
        .pma_instruction_fetch_exception_o(pma_instruction_fetch_exception),
        .pma_write_exception_o            (pma_write_exception),
        .pma_read_exception_o             (pma_read_exception),
        .hardware_fault_o                 (memory_checker_hardware_fault),
        .pma_faulting_addr_o              (pma_faulting_addr),
        .pmp_write_exception_o            (pmp_write_exception),
        .pmp_read_exception_o             (pmp_read_exception),
        .pmp_instruction_fetch_exception_o(pmp_instruction_fetch_exception),
        .pmp_faulting_addr_o              (pmp_faulting_addr)
    );
endmodule

module riscv_system (
    input logic clk,
    input logic rst_n
);
    // Wire instantiations (_i and _o suffixes from perspective of riscv_core)
    logic [IALIGN-1:0] inst_i;
    logic [WWIDTH-1:0] data_mem_data_i, data_mem_data_o;
    logic [XLEN-1:0] pc_o, data_mem_addr_o;
    logic [WWIDTH/8-1:0] data_mem_we_o;

    // CPU core
    riscv_core u_riscv_core (
        .clk                (clk),
        .rst_n              (rst_n),
        .inst_i             (inst_i),
        .data_mem_data_i    (data_mem_data_i),
        .pc_o               (pc_o),
        .data_mem_we_o      (data_mem_we_o),
        .data_mem_addr_o    (data_mem_addr_o),
        .data_mem_data_o    (data_mem_data_o)
    );

    // All memory, from the start of IMEM to end of DMEM.
    sram #(
        .DWIDTH           (WWIDTH),
        .NUM_BYTES        (WWIDTH/8),
        .AWIDTH           (XLEN),
        .START_ADDRESS    (MEM_START_ADDRESS),
        .END_ADDRESS      (MEM_END_ADDRESS)
    ) data_sram (
        .clk              (clk),
        .address_1_i      (data_mem_addr_o),
        .address_2_i      (pc_o),
        .data_i           (data_mem_data_o),
        .we_i             (data_mem_we_o),
        .data_1_o         (data_mem_data_i),
        .data_2_o         (inst_i)
    );
endmodule
