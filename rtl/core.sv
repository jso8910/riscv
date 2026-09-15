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
    trap_t wb_trap;
    mem_res_t [1:0] mem_res;
    // One speculation we make is that the machine_privilege will not change before writeback. As a
    // result, we flush the pipeline on privilege change.
    machine_privilege_t machine_privilege;
    logic [XLEN-1:0] rs1_data, csr_val,
                     alu_res, mem_content, mepc, mtvec,
                     mstatus, inst_mem_fault_addr_q, inst_page_fault_addr_q,
                     stimecmp, mip, mie, sie, medeleg, mideleg,
                     mtimecmp, sip, stvec, sepc, fetch_page_fault_addr,
                     satp;
    logic csr_illegal_inst, retire_count, cycle_tick, wb_valid, wb_retire, wb_take_trap,
          hardware_fault, inst_page_fault_q, data_ptw_stall, pc_ptw_stall,
          mtimecmp_we, mtip, stip, ptw_flush, fetch_page_fault,
          load_page_fault, store_page_fault, mem_valid;
    logic [XLEN-1:0] mem_store_data;

    pmp_decoded_entry_t pmp_decoded [0:PMP_ENTRY_COUNT-1];

    mem_fault_t [MEM_READ_PORTS-1:0] mem_fault, mem_fault_q;
    mem_fault_t inst_mem_fault_q;
    logic [MEM_READ_PORTS-1:0][XLEN-1:0] mem_fault_addr, mem_fault_addr_q;
    mem_req_t [MEM_READ_PORTS-1:0] mem_req;
    ctrl_t mem_ctrl, wb_ctrl;

    // ===========
    // Assignments
    // ===========
    // mem_fault and mem_fault_addr are partially buffered to take into account that fetches happen
    // speculatively one instruction in advance
    assign mem_fault_q[0] = mem_fault[0];
    assign mem_fault_q[1] = inst_mem_fault_q;
    assign mem_fault_addr_q[0] = mem_fault_addr[0];
    assign mem_fault_addr_q[1] = inst_mem_fault_addr_q;

    assign data_mem_data_o = mem_store_data;
    assign data_mem_addr_o = mem_req[0].address;
    assign inst_mem_addr_o = mem_req[1].address;

    assign mem_content = mem_res[0].data;
    assign cycle_tick = '1;
    assign retire_count = wb_retire;

    // hardware fault logic (none so far)
    assign hardware_fault = '0;

    // =====================
    // =====================
    // Module instantiations
    // =====================
    // =====================

    // ==
    // IF
    // ==
    logic ex_redirect, ex_redirect_raw, wb_trap_redirect, if_flush, wb_csr_redirect;
    logic [XLEN-1:0] ex_redirect_pc, wb_redirect_pc, redirect_pc, wb_pred_pc;
    mem_fault_t if_fetch_mem_fault;
    logic if_fetch_page_fault, if_ready, if_valid;
    logic [XLEN-1:0] if_fetch_pc, if_inst_pc, if_inst_pred_pc, if_fetch_page_fault_addr,
                     if_fetch_mem_fault_addr, if_pred_pc;
    logic [IALIGN-1:0] if_inst;
    // A frontend flush invalidates the request context of an in-flight PTW.
    assign ptw_flush = if_flush;
    fetch u_fetch (
        .clk          (clk),
        .rst_n        (rst_n),
        .if_pred_pc_i (if_pred_pc),
        .redirect_i   (if_flush),
        .redirect_pc_i(redirect_pc),
        .fetch_mem_res_i(mem_res[1]),
        .fetch_mem_req_i(mem_req[1]),
        .fetch_page_fault_i(fetch_page_fault),
        .fetch_page_fault_addr_i(fetch_page_fault_addr),
        .fetch_mem_fault_addr_i(mem_fault_addr[1]),
        .fetch_mem_fault_i(mem_fault[1]),
        .if_ready     (if_ready),
        .inst_pc_o    (if_inst_pc),
        .inst_pred_pc_o(if_inst_pred_pc),
        .fetch_pc_o   (if_fetch_pc),
        .inst_o       (if_inst),
        .if_valid_o (if_valid),
        .inst_mem_fault_q(if_fetch_mem_fault),
        .inst_mem_fault_addr_q(if_fetch_mem_fault_addr),
        .inst_page_fault_q(if_fetch_page_fault),
        .inst_page_fault_addr_q(if_fetch_page_fault_addr)
    );

    // Redirect PC selection logic - redirects from earlier stages take precedene
    always_comb begin
        redirect_pc = '0;
        if (wb_trap_redirect) begin
            redirect_pc = wb_redirect_pc;
        end else if (wb_csr_redirect) begin
            // xRET changes privilege as well as control flow, so replay from its
            // architectural return PC after the WB state update.
            if (wb_ctrl.mret) begin
                redirect_pc = mepc;
            end else if (wb_ctrl.sret) begin
                redirect_pc = sepc;
            end else begin
                redirect_pc = wb_pred_pc;
            end
        end else if (ex_redirect) begin
            redirect_pc = ex_redirect_pc;
        end
    end

    memory_controller inst_mem_ctrl (
        .data_i       (inst_mem_data_i),
        .mtime_i      (time_i),
        .mtimecmp_i   (mtimecmp),
        .mem_req_i    (mem_req[1]),
        .commit_i     (wb_retire),
        .res_o        (mem_res[1]),
        // This memory controller can't write
        .we_o         (),
        .mtime_we_o   (),
        .mtimecmp_we_o()
    );

    pc_prediction pc_prediction (
        .if_fetch_pc_i(if_fetch_pc),
        .if_pred_pc_o (if_pred_pc)
    );

    // TODO: move this to a later stage (writeback)
    // next_pc_unit u_next_pc_unit (
    //     .ctrl_i        (ctrl),
    //     .pc_i          (inst_pc),
    //     .rs1_data_i    (rs1_data),
    //     .rs2_data_i    (rs2_data),
    //     .alu_res_i     (alu_res),
    //     .mepc_i        (mepc),
    //     .mtvec_i       (mtvec),
    //     .sepc_i        (sepc),
    //     .stvec_i       (stvec),
    //     .trap_i        (trap),
    //     .next_pc_o     (next_pc),
    //     .address_misaligned_o (address_misaligned)
    // );

    // ==============
    // IF/ID Register
    // ==============
    logic if_id_stall, id_ready, id_valid, id_fetch_page_fault, id_flush;
    mem_fault_t id_fetch_mem_fault;
    logic [XLEN-1:0] id_pc, id_fetch_mem_fault_addr, id_fetch_page_fault_addr, id_pred_pc;
    logic [IALIGN-1:0] id_inst;
    if_id_reg if_id_reg (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .stall_i                   (if_id_stall),
        .id_flush_i                (id_flush),
        .if_flush_o                (if_flush),
        .if_valid_i                (if_valid),
        .if_ready_o                (if_ready),
        .if_pc_i                   (if_inst_pc),
        .if_pred_pc_i              (if_inst_pred_pc),
        .if_inst_i                 (if_inst),
        .if_fetch_mem_fault_i      (if_fetch_mem_fault),
        .if_fetch_mem_fault_addr_i (if_fetch_mem_fault_addr),
        .if_fetch_page_fault_i     (if_fetch_page_fault),
        .if_fetch_page_fault_addr_i(if_fetch_page_fault_addr),
        .id_ready_i                (id_ready),
        .id_valid_o                (id_valid),
        .id_pc_o                   (id_pc),
        .id_pred_pc_o              (id_pred_pc),
        .id_inst_o                 (id_inst),
        .id_fetch_mem_fault_o      (id_fetch_mem_fault),
        .id_fetch_mem_fault_addr_o (id_fetch_mem_fault_addr),
        .id_fetch_page_fault_o     (id_fetch_page_fault),
        .id_fetch_page_fault_addr_o(id_fetch_page_fault_addr)
    );

    // The only situation where a stall is necessary is if the page table walker is working on
    // getting an instruction. However, this is already implicitly handled by the fetch unit looking
    // for mem_res.valid.
    assign if_id_stall = '0;

    // ==============
    // Decode/control
    // ==============
    logic [XLEN-1:0] id_imm, id_rs1_data, id_rs2_data, id_rs1_data_rf, id_rs2_data_rf, id_csr_data_read_raw;
    ctrl_t id_ctrl;
    control_unit u_control_unit (
        .inst_i    (id_inst),
        .inst_valid_i(id_valid),
        // Speculation: machine_privilege will not change before WB
        .current_privilege_i(machine_privilege),
        .imm_o     (id_imm),
        .ctrl_o    (id_ctrl)
    );

    // =================
    // WB->ID Forwarding
    // =================
    logic [XLEN-1:0] wb_rd_data, wb_rd_data_raw;
    always_comb begin
        id_rs1_data = id_rs1_data_rf;
        id_rs2_data = id_rs2_data_rf;
        if (wb_retire && wb_ctrl.reg_write && wb_ctrl.rd_addr == id_ctrl.rs1_addr && wb_ctrl.rd_addr != X0)
            id_rs1_data = wb_rd_data;
        if (wb_retire && wb_ctrl.reg_write && wb_ctrl.rd_addr == id_ctrl.rs2_addr && wb_ctrl.rd_addr != X0)
            id_rs2_data = wb_rd_data;
    end

    // ==============
    // ID/EX Register
    // ==============
    mem_fault_t ex_fetch_mem_fault;
    logic id_ex_stall, ex_ready, ex_valid, ex_fetch_page_fault, ex_flush;
    logic [XLEN-1:0] ex_pc, ex_imm, ex_fetch_mem_fault_addr, ex_fetch_page_fault_addr, ex_pred_pc,
                     ex_rs1_data_raw, ex_rs2_data_raw, ex_csr_data_read_raw;
    ctrl_t ex_ctrl;
    id_ex_reg id_ex_reg (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .stall_i                   (id_ex_stall),
        .ex_flush_i                (ex_flush | ex_redirect),
        .id_flush_o                (id_flush),
        .id_valid_i                (id_valid),
        .id_ready_o                (id_ready),
        .id_pc_i                   (id_pc),
        .id_pred_pc_i              (id_pred_pc),
        .id_ctrl_i                 (id_ctrl),
        .id_rs1_data_raw_i         (id_rs1_data),
        .id_rs2_data_raw_i         (id_rs2_data),
        .id_csr_data_read_raw_i    (id_csr_data_read_raw),
        .id_imm_i                  (id_imm),
        .id_fetch_mem_fault_i      (id_fetch_mem_fault),
        .id_fetch_mem_fault_addr_i (id_fetch_mem_fault_addr),
        .id_fetch_page_fault_i     (id_fetch_page_fault),
        .id_fetch_page_fault_addr_i(id_fetch_page_fault_addr),
        .ex_ready_i                (ex_ready),
        .ex_valid_o                (ex_valid),
        .ex_pc_o                   (ex_pc),
        .ex_pred_pc_o              (ex_pred_pc),
        .ex_ctrl_o                 (ex_ctrl),
        .ex_rs1_data_raw_o         (ex_rs1_data_raw),
        .ex_rs2_data_raw_o         (ex_rs2_data_raw),
        .ex_csr_data_read_raw_o    (ex_csr_data_read_raw),
        .ex_imm_o                  (ex_imm),
        .ex_fetch_mem_fault_o      (ex_fetch_mem_fault),
        .ex_fetch_mem_fault_addr_o (ex_fetch_mem_fault_addr),
        .ex_fetch_page_fault_o     (ex_fetch_page_fault),
        .ex_fetch_page_fault_addr_o(ex_fetch_page_fault_addr)
    );

    // ===========
    // Hazard unit
    // ===========
    logic load_use_hazard, late_csr_use_hazard, csr_interlock_hazard;
    hazard_unit hazard_unit (
        .ex_valid_i       (ex_valid),
        .mem_valid_i      (mem_valid),
        .wb_valid_i       (wb_valid),
        .ex_ctrl_i        (ex_ctrl),
        .mem_ctrl_i       (mem_ctrl),
        .wb_ctrl_i        (wb_ctrl),
        .id_ctrl_i        (id_ctrl),
        .load_use_hazard_o(load_use_hazard),
        .late_csr_use_hazard_o(late_csr_use_hazard),
        .csr_interlock_hazard_o(csr_interlock_hazard)
    );

    assign id_ex_stall = load_use_hazard || late_csr_use_hazard || csr_interlock_hazard;

    // ===============
    // Forwarding unit
    // ===============
    logic [XLEN-1:0] ex_rs1_data, ex_rs2_data, ex_csr_data_read, mem_rd_data, mem_csr_data_write,
                     mem_csr_operand, wb_csr_data_write, wb_csr_data_write_raw, wb_csr_operand,
                     wb_csr_data_read_late, wb_late_csr_data_write;
    logic wb_late_csr_access;
    forwarding_unit forwarding_unit (
        .ex_ctrl_i     (ex_ctrl),
        .ex_rs1_data_raw_i  (ex_rs1_data_raw),
        .ex_rs2_data_raw_i  (ex_rs2_data_raw),
        .ex_csr_data_raw_i  (ex_csr_data_read_raw),
        .mem_valid_i   (mem_valid),
        .mem_ctrl_i    (mem_ctrl),
        .mem_rd_data_i (mem_rd_data),
        .wb_valid_i    (wb_valid),
        .wb_ctrl_i     (wb_ctrl),
        .wb_rd_data_i  (wb_rd_data),
        .ex_rs1_data_o (ex_rs1_data),
        .ex_rs2_data_o (ex_rs2_data),
        .ex_csr_data_o (ex_csr_data_read)
    );

    logic [XLEN-1:0] ex_csr_data_write, ex_csr_operand;
    assign ex_csr_operand = ex_ctrl.csr_imm ? XLEN'(ex_ctrl.rs1_addr) : ex_rs1_data;
    csr_val_gen csr_val_gen (
        .ctrl_i    (ex_ctrl),
        .rs1_data_i(ex_rs1_data),
        .csr_val_i (ex_csr_data_read),
        .csr_data_o(ex_csr_data_write)
    );

    // =============
    // Operand 1 mux
    // =============
    logic [XLEN-1:0] ex_op1;
    always_comb begin
        case (ex_ctrl.op1_src)
            RS1 : ex_op1 = ex_rs1_data;
            PC : ex_op1 = ex_pc;
            default: $fatal(1);
        endcase
    end

    // =======
    // Execute
    // =======
    logic [XLEN-1:0] ex_alu_res;
    alu u_alu (
        .ctrl_i        (ex_ctrl),
        .op1_data_i    (ex_op1),
        .op2_data_i    (ex_rs2_data),
        .imm_i         (ex_imm),
        .res_o         (ex_alu_res)
    );

    sfence_sel_t ex_sfence_sel;
    sfence_selector u_sfence_selector (
        .ctrl_i      (ex_ctrl),
        .rs1_data_i  (ex_rs1_data),
        .rs2_data_i  (ex_rs2_data),
        .sfence_sel_o(ex_sfence_sel)
    );

    // ============
    // Rd value mux
    // ============
    logic [XLEN-1:0] ex_rd_data;
    always_comb begin
        ex_rd_data = '0;
        case (ex_ctrl.wb_sel)
            WB_ALU : ex_rd_data = ex_alu_res;
            // this will be filled in after MEM. since we insert a stall for load-use hazards, this
            // value will never end up being used
            WB_MEM : ex_rd_data = '0;
            WB_IMM : ex_rd_data = ex_imm;
            WB_PC_PLUS_4 : ex_rd_data = ex_pc + PC_INC;
            WB_CSR : ex_rd_data = ex_csr_data_read;
            default : $fatal(1);
        endcase
    end

    // =======
    // Next PC
    // =======
    logic ex_address_misaligned;
    next_pc_unit next_pc_unit (
        .ctrl_i              (ex_ctrl),
        .pc_i                (ex_pc),
        .pred_pc_i           (ex_pred_pc),
        .rs1_data_i          (ex_rs1_data),
        .rs2_data_i          (ex_rs2_data),
        .alu_res_i           (ex_alu_res),
        // SPECULATION: mepc and sepc won't change before WB
        .mepc_i              (mepc),
        // .mtvec_i             (mtvec_i),
        .sepc_i              (sepc),
        // .stvec_i             (stvec_i),
        // .trap_i              (trap_i),
        .next_pc_o           (ex_redirect_pc),
        .redirect_o          (ex_redirect_raw),
        .address_misaligned_o(ex_address_misaligned)
    );
    // next_pc_unit is combinational and its reset/bubble inputs need not
    // predict sequentially; only a valid EX instruction may redirect.
    assign ex_redirect = ex_valid && ex_redirect_raw;

    // ===============
    // EX/MEM Register
    // ===============
    logic ex_mem_stall, mem_ready, mem_fetch_page_fault, mem_flush, mem_address_misaligned;
    logic [XLEN-1:0] mem_pc, mem_fetch_mem_fault_addr, mem_fetch_page_fault_addr, mem_pred_pc,
                     mem_addr;
    sfence_sel_t mem_sfence_sel, wb_sfence_sel;
    mem_fault_t mem_fetch_mem_fault;
    ex_mem_reg ex_mem_reg (
        .clk                        (clk),
        .rst_n                      (rst_n),
        .stall_i                    (ex_mem_stall),
        .mem_flush_i                (mem_flush),
        .ex_flush_o                 (ex_flush),
        .ex_valid_i                 (ex_valid),
        .ex_ready_o                 (ex_ready),
        .ex_pc_i                    (ex_pc),
        .ex_pred_pc_i               (ex_pred_pc),
        .ex_ctrl_i                  (ex_ctrl),
        .ex_sfence_sel_i            (ex_sfence_sel),
        .ex_addr_i                  (ex_alu_res),
        .ex_store_data_i            (ex_rs2_data),
        .ex_rd_data_i               (ex_rd_data),
        .ex_csr_data_write_i        (ex_csr_data_write),
        .ex_csr_operand_i           (ex_csr_operand),
        .ex_fetch_mem_fault_i       (ex_fetch_mem_fault),
        .ex_fetch_mem_fault_addr_i  (ex_fetch_mem_fault_addr),
        .ex_fetch_page_fault_i      (ex_fetch_page_fault),
        .ex_fetch_page_fault_addr_i (ex_fetch_page_fault_addr),
        .ex_address_misaligned_i    (ex_address_misaligned),
        .mem_ready_i                (mem_ready),
        .mem_valid_o                (mem_valid),
        .mem_pc_o                   (mem_pc),
        .mem_pred_pc_o              (mem_pred_pc),
        .mem_ctrl_o                 (mem_ctrl),
        .mem_sfence_sel_o           (mem_sfence_sel),
        .mem_addr_o                 (mem_addr),
        .mem_store_data_o           (mem_store_data),
        .mem_rd_data_o              (mem_rd_data),
        .mem_csr_data_write_o       (mem_csr_data_write),
        .mem_csr_operand_o          (mem_csr_operand),
        .mem_fetch_mem_fault_o      (mem_fetch_mem_fault),
        .mem_fetch_mem_fault_addr_o (mem_fetch_mem_fault_addr),
        .mem_fetch_page_fault_o     (mem_fetch_page_fault),
        .mem_fetch_page_fault_addr_o(mem_fetch_page_fault_addr),
        .mem_address_misaligned_o   (mem_address_misaligned)
    );

    assign ex_mem_stall = '0;

    // =========
    // MEM stage
    // =========
    logic mem_data_store_page_fault, mem_data_load_page_fault, mem_store_commit;
    logic [XLEN-1:0] mem_data_page_fault_addr;
    memory_management_unit memory_management_unit (
        .clk                (clk),
        .rst_n              (rst_n),
        .commit_i           (wb_retire),
        .mem_valid_i        (mem_valid),
        .ctrl_mem_i         (mem_ctrl),
        .sfence_sel_i       (wb_sfence_sel),
        .addr_i             (mem_addr),
        .pc_i               (if_fetch_pc),
        .mem_res_i          (mem_res),
        // SPECULATION: mstatus and satp will not change before WB
        // PMPs are checked on every final physical request, including TLB hits and PTW reads, so a
        // PMP change does not require a TLB invalidation. The pipeline is flushed on SFENCE.VMA.
        .pmp_decoded_i      (pmp_decoded),
        .ptw_flush_i        (ptw_flush),
        .current_privilege_i(machine_privilege),
        .mstatus_i          (mstatus),
        .satp_i             (satp),
        .mem_req_o          (mem_req),
        .data_ptw_stall_o   (data_ptw_stall),
        .pc_ptw_stall_o     (pc_ptw_stall),
        .load_page_fault_o  (mem_data_load_page_fault),
        .store_page_fault_o (mem_data_store_page_fault),
        .fetch_page_fault_o (fetch_page_fault),
        .page_fault_addr_a_o(mem_data_page_fault_addr),
        .page_fault_addr_b_o(fetch_page_fault_addr),
        .mem_fault_o        (mem_fault),
        .mem_fault_addr_o   (mem_fault_addr)
    );

    // Stores execute in MEM, so permit their side effect only after all older
    // instructions are known not to redirect and after this store is fault-free.
    assign mem_store_commit = mem_valid && mem_ctrl.mem_write && !wb_csr_redirect
                              && (!wb_valid || !wb_trap.is_trap)
                              && mem_fault[0] == FAULT_NONE && !mem_data_store_page_fault;

    // Each memory controller is for a separate read port
    memory_controller data_mem_ctrl (
        .data_i       (data_mem_data_i),
        .mtime_i      (time_i),
        .mtimecmp_i   (mtimecmp),
        .mem_req_i    (mem_req[0]),
        .commit_i     (mem_store_commit),
        .res_o        (mem_res[0]),
        .we_o         (data_mem_we_o),
        .mtime_we_o   (mtime_we_o),
        .mtimecmp_we_o(mtimecmp_we)
    );

    // ===============
    // MEM/WB Register
    // ===============
    logic mem_wb_stall, wb_ready, wb_fetch_page_fault, wb_data_store_page_fault,
          wb_data_load_page_fault, wb_address_misaligned;
    logic [XLEN-1:0] wb_pc, wb_fetch_mem_fault_addr, wb_fetch_page_fault_addr, wb_data_mem_fault_addr,
                     wb_data_page_fault_addr;
    mem_fault_t wb_fetch_mem_fault, wb_data_mem_fault;
    mem_wb_reg mem_wb_reg (
        .clk                        (clk),
        .rst_n                      (rst_n),
        .stall_i                    (mem_wb_stall),
        .wb_flush_i                 (wb_csr_redirect | wb_trap_redirect),
        .mem_flush_o                (mem_flush),
        .mem_data_res_i             (mem_res[0]),
        .mem_valid_i                (mem_valid),
        .mem_ready_o                (mem_ready),
        .mem_pc_i                   (mem_pc),
        .mem_pred_pc_i              (mem_pred_pc),
        .mem_ctrl_i                 (mem_ctrl),
        .mem_sfence_sel_i           (mem_sfence_sel),
        .mem_rd_data_i              (mem_rd_data),
        .mem_csr_data_write_i       (mem_csr_data_write),
        .mem_csr_operand_i          (mem_csr_operand),
        .mem_fetch_mem_fault_i      (mem_fetch_mem_fault),
        .mem_fetch_mem_fault_addr_i (mem_fetch_mem_fault_addr),
        .mem_fetch_page_fault_i     (mem_fetch_page_fault),
        .mem_fetch_page_fault_addr_i(mem_fetch_page_fault_addr),
        .mem_data_mem_fault_i       (mem_fault[0]),
        .mem_data_mem_fault_addr_i  (mem_fault_addr[0]),
        .mem_data_store_page_fault_i(mem_data_store_page_fault),
        .mem_data_load_page_fault_i (mem_data_load_page_fault),
        .mem_data_page_fault_addr_i (mem_data_page_fault_addr),
        .mem_address_misaligned_i   (mem_address_misaligned),
        .wb_valid_o                 (wb_valid),
        .wb_ready_i                 (wb_ready),
        .wb_pc_o                    (wb_pc),
        .wb_pred_pc_o               (wb_pred_pc),
        .wb_ctrl_o                  (wb_ctrl),
        .wb_sfence_sel_o            (wb_sfence_sel),
        .wb_rd_data_o               (wb_rd_data_raw),
        .wb_csr_data_write_o        (wb_csr_data_write_raw),
        .wb_csr_operand_o           (wb_csr_operand),
        .wb_fetch_mem_fault_o       (wb_fetch_mem_fault),
        .wb_fetch_mem_fault_addr_o  (wb_fetch_mem_fault_addr),
        .wb_fetch_page_fault_o      (wb_fetch_page_fault),
        .wb_fetch_page_fault_addr_o (wb_fetch_page_fault_addr),
        .wb_data_mem_fault_o        (wb_data_mem_fault),
        .wb_data_mem_fault_addr_o   (wb_data_mem_fault_addr),
        .wb_data_store_page_fault_o (wb_data_store_page_fault),
        .wb_data_load_page_fault_o  (wb_data_load_page_fault),
        .wb_data_page_fault_addr_o  (wb_data_page_fault_addr),
        .wb_address_misaligned_o    (wb_address_misaligned)
    );

    assign mem_wb_stall = data_ptw_stall;

    // TODO: is this correct? i think so?
    assign wb_ready = '1;

    assign wb_late_csr_access = wb_ctrl.wb_sel == WB_CSR && is_late_csr(wb_ctrl.csr_addr);
    csr_val_gen wb_csr_val_gen (
        .ctrl_i    (wb_ctrl),
        .rs1_data_i(wb_csr_operand),
        .csr_val_i (wb_csr_data_read_late),
        .csr_data_o(wb_late_csr_data_write)
    );
    always_comb begin
        wb_rd_data = wb_rd_data_raw;
        wb_csr_data_write = wb_csr_data_write_raw;
        if (wb_late_csr_access) begin
            wb_rd_data = wb_csr_data_read_late;
            wb_csr_data_write = wb_late_csr_data_write;
        end
    end

    // =======================
    // Register file/writeback
    // =======================
    regfile u_regfile (
        .clk           (clk),
        .rst_n         (rst_n),
        .rs1_addr_i    (id_ctrl.rs1_addr),
        .rs2_addr_i    (id_ctrl.rs2_addr),
        .rd_addr_i     (wb_ctrl.rd_addr),
        .reg_write_i   (wb_ctrl.reg_write),
        .commit_i      (wb_retire),
        .rd_data_i     (wb_rd_data),
        .rs1_data_o    (id_rs1_data_rf),
        .rs2_data_o    (id_rs2_data_rf)
    );

    // ========
    // CSR file
    // ========
    csrfile u_csrfile (
        .clk                (clk),
        .rst_n              (rst_n),
        .commit_i           (wb_retire),
        .trap_take_i        (wb_take_trap),
        .ctrl_i             (wb_ctrl),
        .cycle_tick_i       (cycle_tick),
        .retire_count_i     (retire_count),
        .csr_data_i         (wb_csr_data_write),
        .csr_read_addr_i    (id_ctrl.csr_addr),
        .csr_late_read_addr_i(wb_ctrl.csr_addr),
        .trap_i             (wb_trap),
        .mtip_i             (mtip),
        .stip_i             (stip),
        .time_i             (time_i),
        .csr_val_o          (id_csr_data_read_raw),
        .csr_late_val_o     (wb_csr_data_read_late),
        .mepc_o             (mepc),
        .mtvec_o            (mtvec),
        .sepc_o             (sepc),
        .stvec_o            (stvec),
        .mstatus_o          (mstatus),
        .stimecmp_o         (stimecmp),
        .pmp_cfg_o          (),
        .pmp_addr_o         (),
        .pmp_decoded_o      (pmp_decoded),
        .mip_o              (mip),
        .mie_o              (mie),
        .sip_o              (sip),
        .sie_o              (sie),
        .satp_o             (satp),
        .medeleg_o          (medeleg),
        .mideleg_o          (mideleg),
        .csr_illegal_inst_o (csr_illegal_inst),
        .machine_privilege_o(machine_privilege),
        .csr_flush_o        (wb_csr_redirect)
    );

    // ===============
    // Trap controller
    // ===============
    trap_controller u_trap_controller (
        .ctrl_i               (wb_ctrl),
        .hardware_fault_i     (hardware_fault),
        .csr_illegal_inst_i   (csr_illegal_inst),
        .address_misaligned_i (wb_address_misaligned),

        .data_mem_fault_i     (wb_data_mem_fault),
        .data_mem_fault_addr_i(wb_data_mem_fault_addr),
        .fetch_mem_fault_i     (wb_fetch_mem_fault),
        .fetch_mem_fault_addr_i(wb_fetch_mem_fault_addr),
        .load_page_fault_i    (wb_data_load_page_fault),
        .store_page_fault_i   (wb_data_store_page_fault),
        .fetch_page_fault_i   (wb_fetch_page_fault),
        // instruction page fault takes priority.
        .page_fault_addr_i    (wb_fetch_page_fault ? wb_fetch_page_fault_addr : wb_data_page_fault_addr),

        .mip_i               (mip),
        .mie_i               (mie),
        .sip_i               (sip),
        .sie_i               (sie),
        .mstatus_i           (mstatus),
        .mideleg_i           (mideleg),
        .medeleg_i           (medeleg),
        .current_privilege_i (machine_privilege),
        .pc_i                (wb_pc),
        .trap_o              (wb_trap)
    );

    trap_pc u_trap_pc (
        .commit_i       (wb_take_trap),
        .trap_i         (wb_trap),
        .mtvec_i        (mtvec),
        .stvec_i        (stvec),
        .next_pc_o      (wb_redirect_pc),
        .trap_redirect_o(wb_trap_redirect)
    );

    // A trap is accepted before the WB instruction retires, so it suppresses
    // every effect of that instruction.  CSR trap-state updates use the
    // separate take signal rather than the retirement signal.
    assign wb_take_trap = wb_valid && wb_trap.is_trap;
    assign wb_retire = wb_valid && !wb_trap.is_trap;

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
endmodule : riscv_core

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
