import riscv::*;

module hazard_unit (
    input logic ex_valid_i,
    input logic mem_valid_i,
    input logic wb_valid_i,
    input ctrl_t id_ctrl_i,
    input ctrl_t ex_ctrl_i,
    input ctrl_t mem_ctrl_i,
    input ctrl_t wb_ctrl_i,

    output logic load_use_hazard_o,
    output logic late_csr_use_hazard_o,
    output logic csr_interlock_hazard_o
);
    // If we load data into a register then immediately use it, we must insert a one-cycle bubble.
    // In this case, the instruction with the hazard is in the IF stage (IF/ID register), so we
    // change the ready signal of ID/EX to 0 so the instruction is stuck in the ID stage for an
    // extra cycle.
    logic ex_is_load;
    assign ex_is_load = (ex_ctrl_i.wb_sel == WB_MEM);

    // If EX writes r0, r0 has no dependency on the memory access
    logic ex_writes_valid_rd;
    assign ex_writes_valid_rd = ex_valid_i && ex_ctrl_i.reg_write && ex_ctrl_i.rd_addr != X0;

    logic id_reads_rs1, id_reads_rs2, id_reads_ex_rd;
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
    assign id_reads_ex_rd = (id_reads_rs1 && ex_ctrl_i.rd_addr == id_ctrl_i.rs1_addr)
                         || (id_reads_rs2 && ex_ctrl_i.rd_addr == id_ctrl_i.rs2_addr);

    assign load_use_hazard_o = ex_is_load & ex_writes_valid_rd & id_reads_ex_rd;

    // cycle/time/instret reads are deliberately sampled in WB, rather than on the normal CSR
    // read path in ID: their architectural value must include the counter updates that occur
    // while the instruction is in flight.  Consequently, an immediately following consumer
    // would otherwise reach EX before its producer has its WB-sampled result.  Hold the consumer
    // in ID for one cycle; it then reaches EX when the producer is in WB and receives the result
    // through the existing WB-to-ID/EX forwarding paths.  Ordinary CSR reads still use their ID
    // value and therefore do not need this interlock.
    assign late_csr_use_hazard_o = ex_valid_i && ex_ctrl_i.wb_sel == WB_CSR
                                 && is_late_csr(ex_ctrl_i.csr_addr) && ex_writes_valid_rd
                                 && id_reads_ex_rd;

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
                                  && ((ex_valid_i && ex_ctrl_i.csr_write
                                       && csr_backing_addr(ex_ctrl_i.csr_addr) == csr_backing_addr(id_ctrl_i.csr_addr))
                                      || (mem_valid_i && mem_ctrl_i.csr_write
                                          && csr_backing_addr(mem_ctrl_i.csr_addr) == csr_backing_addr(id_ctrl_i.csr_addr))
                                      || (wb_valid_i && wb_ctrl_i.csr_write
                                          && csr_backing_addr(wb_ctrl_i.csr_addr) == csr_backing_addr(id_ctrl_i.csr_addr)));
endmodule : hazard_unit
