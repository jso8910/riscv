import riscv::*;

module riscv_core (
    input logic                 clk,
    input logic                 rst_n,
    input logic [WWIDTH-1:0]      inst_mem_data_i,
    input logic [WWIDTH-1:0]    data_mem_data_i,
    input logic [XLEN-1:0]      time_i,

    output logic [XLEN-1:0]     inst_mem_addr_o,
    output logic [WWIDTH/8-1:0] data_mem_we_o,
    output logic [XLEN-1:0]     data_mem_addr_o,
    output logic [WWIDTH-1:0]   data_mem_data_o,
    output logic                mtime_we_o
);
    // ================
    // Wire definitions
    // ================
    ctrl_t ctrl;
    trap_t trap;
    mem_res_t [1:0] mem_res;
    machine_privilege_t machine_privilege;
    logic [XLEN-1:0] next_pc, rs1_data, rs2_data, csr_val,
                     alu_res, imm, mem_content, op1, mepc, mtvec,
                     mstatus, inst_mem_fault_addr_q, inst_page_fault_addr_q,
                     stimecmp, mip, mie, sie, medeleg, mideleg,
                     mtimecmp, sip, stvec, sepc, page_fault_addr,
                     satp, inst_pc, fetch_pc;
    logic csr_illegal_inst, commit, retire_count, cycle_tick, address_misaligned,
          hardware_fault, inst_page_fault_q, data_ptw_stall, pc_ptw_stall,
          mtimecmp_we, mtip, stip, ptw_flush,
          load_page_fault, store_page_fault, fetch_page_fault, inst_valid;

    logic [7:0]      pmp_cfg [0:63];
    logic [XLEN-1:0] pmp_addr [0:63];

    logic [IALIGN-1:0] inst_q;

    mem_fault_t [MEM_READ_PORTS-1:0] mem_fault, mem_fault_q;
    mem_fault_t inst_mem_fault_q;
    logic [MEM_READ_PORTS-1:0][XLEN-1:0] mem_fault_addr, mem_fault_addr_q;
    mem_req_t [MEM_READ_PORTS-1:0] mem_req;

    // ===========
    // Assignments
    // ===========
    // mem_fault and mem_fault_addr are partially buffered to take into account that fetches happen
    // speculatively one instruction in advance
    assign mem_fault_q[0] = mem_fault[0];
    assign mem_fault_q[1] = inst_mem_fault_q;
    assign mem_fault_addr_q[0] = mem_fault_addr[0];
    assign mem_fault_addr_q[1] = inst_mem_fault_addr_q;

    assign data_mem_data_o = rs2_data;
    assign data_mem_addr_o = mem_req[0].address;
    assign inst_mem_addr_o = mem_req[1].address;

    assign mem_content = mem_res[0].data;
    // suppress side effects on trap
    assign commit = ~trap.is_trap & ~data_ptw_stall & inst_valid;
    assign cycle_tick = '1;
    assign retire_count = commit;

    // hardware fault logic (none so far)
    assign hardware_fault = '0;

    // Stop the current PTW if it is interrupted. Currently, that only happens on a trap. In the
    // future, this may happen with branch mispredicts, data hazards, or any cause of a pipeline flush.
    assign ptw_flush = trap.is_trap;

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
        .fetch_mem_res_i(mem_res[1]),
        .fetch_mem_req_i(mem_req[1]),
        .fetch_page_fault_i(fetch_page_fault),
        .fetch_page_fault_addr_i(page_fault_addr),
        .fetch_mem_fault_addr_i(mem_fault_addr[1]),
        .fetch_mem_fault_i(mem_fault[1]),
        .next_pc_i    (next_pc),
        .commit_i     (commit),
        .inst_pc_o    (inst_pc),
        .fetch_pc_o   (fetch_pc),
        .inst_o       (inst_q),
        .inst_valid_o (inst_valid),
        .inst_mem_fault_q(inst_mem_fault_q),
        .inst_mem_fault_addr_q(inst_mem_fault_addr_q),
        .inst_page_fault_q(inst_page_fault_q),
        .inst_page_fault_addr_q(inst_page_fault_addr_q)
    );

    next_pc_unit u_next_pc_unit (
        .ctrl_i        (ctrl),
        .pc_i          (inst_pc),
        .rs1_data_i    (rs1_data),
        .rs2_data_i    (rs2_data),
        .alu_res_i     (alu_res),
        .mepc_i        (mepc),
        .mtvec_i       (mtvec),
        .sepc_i        (sepc),
        .stvec_i       (stvec),
        .trap_i        (trap),
        .next_pc_o     (next_pc),
        .address_misaligned_o (address_misaligned)
    );

    // ==============
    // Decode/control
    // ==============
    control_unit u_control_unit (
        .inst_i    (inst_q),
        .inst_valid_i(inst_valid),
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

        .mem_fault_i         (mem_fault_q),
        .mem_fault_addr_i    (mem_fault_addr_q),
        .load_page_fault_i   (load_page_fault),
        .store_page_fault_i  (store_page_fault),
        .fetch_page_fault_i  (inst_page_fault_q),
        // instruction page fault takes priority. inst_page_fault_addr_q is just page_fault_addr
        // buffered by one cycle
        .page_fault_addr_i   (inst_page_fault_q ? inst_page_fault_addr_q : page_fault_addr),

        .mip_i               (mip),
        .mie_i               (mie),
        .sip_i               (sip),
        .sie_i               (sie),
        .mstatus_i           (mstatus),
        .mideleg_i           (mideleg),
        .medeleg_i           (medeleg),
        .current_privilege_i (machine_privilege),
        .pc_i                (inst_pc),
        .trap_o              (trap)
    );

    timer_interrupt u_timer_interrupt (
        .clk          (clk),
        .rst_n        (rst_n),
        .time_i       (time_i),
        .mtimecmp_i   (data_mem_data_o),
        .mtimecmp_we_i(mtimecmp_we),
        .stimecmp_i   (stimecmp),
        .mtip_o       (mtip),
        .stip_o       (stip),
        .mtimecmp_o   (mtimecmp)
    );

    // =============
    // Operand 1 mux
    // =============
    always_comb begin
        case (ctrl.op1_src)
            RS1 : op1 = rs1_data;
            PC : op1 = inst_pc;
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
        .pc_i          (inst_pc),
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
        .commit_i           (commit),
        .ctrl_i             (ctrl),
        .cycle_tick_i       (cycle_tick),
        .retire_count_i     (retire_count),
        .rs1_i              (rs1_data),
        .trap_i             (trap),
        .mtip_i             (mtip),
        .stip_i             (stip),
        .time_i             (time_i),
        .csr_val_o          (csr_val),
        .mepc_o             (mepc),
        .mtvec_o            (mtvec),
        .sepc_o             (sepc),
        .stvec_o            (stvec),
        .mstatus_o          (mstatus),
        .stimecmp_o         (stimecmp),
        .pmp_cfg_o          (pmp_cfg),
        .pmp_addr_o         (pmp_addr),
        .mip_o              (mip),
        .mie_o              (mie),
        .sip_o              (sip),
        .sie_o              (sie),
        .satp_o             (satp),
        .medeleg_o          (medeleg),
        .mideleg_o          (mideleg),
        .csr_illegal_inst_o (csr_illegal_inst),
        .machine_privilege_o(machine_privilege)
    );

    // ============
    // Memory units
    // ============

    memory_management_unit memory_management_unit (
        .clk                (clk),
        .rst_n              (rst_n),
        .commit_i           (commit),
        .ctrl_i             (ctrl),
        .rs1_data_i         (rs1_data),
        .rs2_data_i         (rs2_data),
        .addr_i             (alu_res),
        .pc_i               (fetch_pc),
        .mem_res_i          (mem_res),
        .pmp_cfg_i          (pmp_cfg),
        .pmp_addr_i         (pmp_addr),
        .ptw_flush_i        (ptw_flush),
        .current_privilege_i(machine_privilege),
        .mstatus_i          (mstatus),
        .satp_i             (satp),
        .mem_req_o          (mem_req),
        .data_ptw_stall_o   (data_ptw_stall),
        .pc_ptw_stall_o     (pc_ptw_stall),
        .load_page_fault_o  (load_page_fault),
        .store_page_fault_o (store_page_fault),
        .fetch_page_fault_o (fetch_page_fault),
        .page_fault_addr_o  (page_fault_addr),
        .mem_fault_o        (mem_fault),
        .mem_fault_addr_o   (mem_fault_addr)
    );

    // Each memory controller is for a separate read port
    memory_controller data_mem_ctrl (
        .data_i       (data_mem_data_i),
        .mtime_i      (time_i),
        .mtimecmp_i   (mtimecmp),
        .mem_req_i    (mem_req[0]),
        .commit_i     (commit),
        .res_o        (mem_res[0]),
        .we_o         (data_mem_we_o),
        .mtime_we_o   (mtime_we_o),
        .mtimecmp_we_o(mtimecmp_we)
    );

    memory_controller inst_mem_ctrl (
        .data_i       (inst_mem_data_i),
        .mtime_i      (time_i),
        .mtimecmp_i   (mtimecmp),
        .mem_req_i    (mem_req[1]),
        .commit_i     (commit),
        .res_o        (mem_res[1]),
        // This memory controller can't write
        .we_o         (),
        .mtime_we_o   (),
        .mtimecmp_we_o()
    );
endmodule

module riscv_system #(
    parameter logic [PHYS_ADDR_WIDTH-1:0] SRAM_END_ADDRESS = MEM_END_ADDRESS
) (
    input logic clk,
    input logic rst_n
);
    // Wire instantiations (_i and _o suffixes from perspective of riscv_core)
    logic [WWIDTH-1:0] data_mem_data_i, data_mem_data_o, data_mem_2;
    logic [XLEN-1:0] inst_mem_addr_o, data_mem_addr_o;
    logic [WWIDTH/8-1:0] data_mem_we_o;
    logic [XLEN-1:0] mtime;
    logic mtime_we;


    // Simple platform timer.  It advances with the core clock and can be set
    // through a store to the MTIME MMIO register.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mtime <= '0;
        else if (mtime_we)
            mtime <= data_mem_data_o;
        else
            mtime <= mtime + XLEN'(1);
    end

    // CPU core
    riscv_core u_riscv_core (
        .clk                (clk),
        .rst_n              (rst_n),
        .inst_mem_data_i    (data_mem_2),
        .data_mem_data_i    (data_mem_data_i),
        .time_i             (mtime),
        .inst_mem_addr_o    (inst_mem_addr_o),
        .data_mem_we_o      (data_mem_we_o),
        .data_mem_addr_o    (data_mem_addr_o),
        .data_mem_data_o    (data_mem_data_o),
        .mtime_we_o         (mtime_we)
    );

    // All memory, from the start of IMEM to end of DMEM.
    sram #(
        .DWIDTH           (WWIDTH),
        .NUM_BYTES        (WWIDTH/8),
        .AWIDTH           (PHYS_ADDR_WIDTH),
        .START_ADDRESS    (MEM_START_ADDRESS[PHYS_ADDR_WIDTH-1:0]),
        .END_ADDRESS      (SRAM_END_ADDRESS)
    ) data_sram (
        .clk              (clk),
        .address_1_i      (data_mem_addr_o[PHYS_ADDR_WIDTH-1:0]),
        .address_2_i      (inst_mem_addr_o[PHYS_ADDR_WIDTH-1:0]),
        .data_i           (data_mem_data_o),
        .we_i             (data_mem_we_o),
        .data_1_o         (data_mem_data_i),
        .data_2_o         (data_mem_2)
    );
endmodule
