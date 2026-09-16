import riscv::*;

module hazard_unit (
    input logic ex1_valid_i,
    input logic ex2_valid_i,
    input logic ex3_valid_i,
    input logic mem_valid_i,
    input logic wb_valid_i,
    input ctrl_t id_ctrl_i,
    input ctrl_t ex1_ctrl_i,
    input ctrl_t ex2_ctrl_i,
    input ctrl_t ex3_ctrl_i,
    input ctrl_t mem_ctrl_i,
    input ctrl_t wb_ctrl_i,

    output logic load_use_hazard_o,
    output logic mul_use_hazard_o,
    output logic late_csr_use_hazard_o,
    output logic csr_interlock_hazard_o
);
    logic id_reads_rs1, id_reads_rs2;
    assign id_reads_rs1 = id_ctrl_i.mem_read || id_ctrl_i.mem_write
                         || (id_ctrl_i.reg_write && id_ctrl_i.wb_sel == WB_ALU
                             && id_ctrl_i.op1_src == RS1)
                         || id_ctrl_i.jalr
                         || (id_ctrl_i.branch && id_ctrl_i.branch_src == SRC_ALU)
                         || id_ctrl_i.tlb_invalidate
                         || (id_ctrl_i.csr_write && !id_ctrl_i.csr_imm);
    assign id_reads_rs2 = id_ctrl_i.mem_write
                         || (id_ctrl_i.reg_write && id_ctrl_i.wb_sel == WB_ALU
                             && !id_ctrl_i.alu_sel_imm)
                         || (id_ctrl_i.branch && id_ctrl_i.branch_src == SRC_ALU)
                         || id_ctrl_i.tlb_invalidate;
    function automatic logic id_reads_producer_rd(input ctrl_t producer_ctrl);
        id_reads_producer_rd = (id_reads_rs1 && producer_ctrl.rd_addr == id_ctrl_i.rs1_addr)
                             || (id_reads_rs2 && producer_ctrl.rd_addr == id_ctrl_i.rs2_addr);
    endfunction

    function automatic logic producer_writes_used_rd(
        input logic producer_valid,
        input ctrl_t producer_ctrl
    );
        producer_writes_used_rd = producer_valid && producer_ctrl.reg_write
                                  && producer_ctrl.rd_addr != X0
                                  && id_reads_producer_rd(producer_ctrl);
    endfunction

    // Load data is first available from WB, so hold its consumer in ID while
    // the load traverses EX1, EX2, EX3, and MEM.
    assign load_use_hazard_o = (producer_writes_used_rd(ex1_valid_i, ex1_ctrl_i)
                                && ex1_ctrl_i.wb_sel == WB_MEM)
                             || (producer_writes_used_rd(ex2_valid_i, ex2_ctrl_i)
                                && ex2_ctrl_i.wb_sel == WB_MEM)
                             || (producer_writes_used_rd(ex3_valid_i, ex3_ctrl_i)
                                && ex3_ctrl_i.wb_sel == WB_MEM)
                             || (producer_writes_used_rd(mem_valid_i, mem_ctrl_i)
                                && mem_ctrl_i.wb_sel == WB_MEM);

    // The multiplier result is unavailable in EX1 and EX2. It can be
    // forwarded from EX3, so no EX3 stall is necessary.
    assign mul_use_hazard_o = (producer_writes_used_rd(ex1_valid_i, ex1_ctrl_i)
                               && ex1_ctrl_i.mul_op != NO_MUL)
                            || (producer_writes_used_rd(ex2_valid_i, ex2_ctrl_i)
                               && ex2_ctrl_i.mul_op != NO_MUL);

    // cycle/time/instret reads are deliberately sampled in WB, rather than on the normal CSR
    // read path in ID: their architectural value must include the counter updates that occur
    // while the instruction is in flight.  Consequently, an immediately following consumer
    // would otherwise reach EX before its producer has its WB-sampled result.  Hold the consumer
    // in ID for one cycle; it then reaches EX when the producer is in WB and receives the result
    // through the existing WB-to-ID/EX forwarding paths.  Ordinary CSR reads still use their ID
    // value and therefore do not need this interlock.
    assign late_csr_use_hazard_o = (producer_writes_used_rd(ex1_valid_i, ex1_ctrl_i)
                                    && ex1_ctrl_i.wb_sel == WB_CSR
                                    && is_late_csr(ex1_ctrl_i.csr_addr))
                                 || (producer_writes_used_rd(ex2_valid_i, ex2_ctrl_i)
                                     && ex2_ctrl_i.wb_sel == WB_CSR
                                     && is_late_csr(ex2_ctrl_i.csr_addr))
                                 || (producer_writes_used_rd(ex3_valid_i, ex3_ctrl_i)
                                     && ex3_ctrl_i.wb_sel == WB_CSR
                                     && is_late_csr(ex3_ctrl_i.csr_addr))
                                 || (producer_writes_used_rd(mem_valid_i, mem_ctrl_i)
                                     && mem_ctrl_i.wb_sel == WB_CSR
                                     && is_late_csr(mem_ctrl_i.csr_addr));

    // CSR read data is sampled in ID. Hold a younger CSR read until an older write to the
    // same backing CSR has committed in WB; otherwise it would observe stale state. The WB
    // cycle must be included because ID/EX captures its input before the WB state update.
    function automatic logic [11:0] csr_backing_addr(input logic [11:0] csr_addr);
        case (csr_addr)
            SSTATUS: csr_backing_addr = MSTATUS;
            SIE:     csr_backing_addr = MIE;
            SIP:     csr_backing_addr = MIP;
            CYCLE:   csr_backing_addr = MCYCLE;
            INSTRET: csr_backing_addr = MINSTRET;
            default: csr_backing_addr = csr_addr;
        endcase
    endfunction

    assign csr_interlock_hazard_o = id_ctrl_i.csr_read
                                  && ((ex1_valid_i && ex1_ctrl_i.csr_write
                                       && csr_backing_addr(ex1_ctrl_i.csr_addr) == csr_backing_addr(id_ctrl_i.csr_addr))
                                      || (ex2_valid_i && ex2_ctrl_i.csr_write
                                          && csr_backing_addr(ex2_ctrl_i.csr_addr) == csr_backing_addr(id_ctrl_i.csr_addr))
                                      || (ex3_valid_i && ex3_ctrl_i.csr_write
                                          && csr_backing_addr(ex3_ctrl_i.csr_addr) == csr_backing_addr(id_ctrl_i.csr_addr))
                                      || (mem_valid_i && mem_ctrl_i.csr_write
                                          && csr_backing_addr(mem_ctrl_i.csr_addr) == csr_backing_addr(id_ctrl_i.csr_addr))
                                      || (wb_valid_i && wb_ctrl_i.csr_write
                                          && csr_backing_addr(wb_ctrl_i.csr_addr) == csr_backing_addr(id_ctrl_i.csr_addr)));
endmodule : hazard_unit
