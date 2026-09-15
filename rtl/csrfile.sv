import riscv::*;

module csrfile (
    input logic                  clk,
    input logic                  rst_n,
    input ctrl_t                 ctrl_i,
    input logic                  commit_i,
    input logic                  trap_take_i,
    input logic                  cycle_tick_i,
    // NOTE: for now, retire_count can only equal 0 or 1 because we don't have a superscalar processor.
    input logic                  retire_count_i,
    input logic [XLEN-1:0]       csr_data_i,
    input logic [11:0]       csr_read_addr_i,
    input logic [11:0]       csr_late_read_addr_i,
    input trap_t                 trap_i,
    input logic                  mtip_i,
    input logic                  stip_i,
    input logic [XLEN-1:0]       time_i,
    output logic [XLEN-1:0]      csr_val_o,
    output logic [XLEN-1:0]      csr_late_val_o,
    output logic [XLEN-1:0]      mepc_o,
    output logic [XLEN-1:0]      mtvec_o,
    output logic [XLEN-1:0]      sepc_o,
    output logic [XLEN-1:0]      stvec_o,
    output logic [XLEN-1:0]      mstatus_o,
    output logic [XLEN-1:0]      stimecmp_o,
    output logic [7:0]           pmp_cfg_o [0:63],
    output logic [XLEN-1:0]      pmp_addr_o [0:63],
    output logic [XLEN-1:0]      mip_o,
    output logic [XLEN-1:0]      mie_o,
    output logic [XLEN-1:0]      sip_o,
    output logic [XLEN-1:0]      sie_o,
    output logic [XLEN-1:0]      medeleg_o,
    output logic [XLEN-1:0]      mideleg_o,
    output logic [XLEN-1:0]      satp_o,
    output logic                 csr_illegal_inst_o,
    output machine_privilege_t   machine_privilege_o,
    output logic                 csr_flush_o
);
    localparam int PMP_ENTRIES_PER_CFG_CSR = XLEN / 8;

    // CSR register definitions
    logic [XLEN-1:0] mepc, mstatus, mtvec, mip, mie, mscratch, mcause,
                     mtval, menvcfg, mseccfg, senvcfg, mcycle, minstret, mcountinhibit,
                     stimecmp, medeleg, mideleg, mcounteren, scounteren,
                     sscratch, sepc, scause, stval, stvec, satp;

    // physical memory protection CSRs
    // Separate arrays avoid an Icarus elaboration failure on variable indexes
    // into an unpacked array of packed structs.
    logic [7:0]      pmp_cfg [0:63];
    logic [XLEN-1:0] pmp_addr [0:63];

    // Some internal signals
    logic            csr_exists;
    logic [3:0]      pmpcfg_index;
    logic [5:0]      pmpaddr_index;

    // Current privilege level
    machine_privilege_t machine_privilege;

    assign pmp_cfg_o = pmp_cfg;
    assign pmp_addr_o = pmp_addr;

    assign csr_exists = csr_addr_exists(ctrl_i.csr_addr);
    assign pmpcfg_index = ctrl_i.csr_addr[3:1] - PMPCFG0[3:1];
    assign pmpaddr_index = ctrl_i.csr_addr[5:0] - PMPADDR0[5:0];

    assign mepc_o = mepc;
    assign mtvec_o = mtvec;
    assign machine_privilege_o = machine_privilege;
    assign mstatus_o = mstatus;
    // With Sstc disabled for S-mode, STIP reverts to software-writable mip behavior.
    assign mip_o = mip | (XLEN'(mtip_i) << M_TIMER)
                     | (XLEN'(stip_i && menvcfg[MENVCFG_STCE]) << S_TIMER);
    assign medeleg_o = medeleg;
    assign mideleg_o = mideleg;
    assign mie_o = mie;

    assign sepc_o = sepc;
    assign stvec_o = stvec;
    assign stimecmp_o = stimecmp;
    assign sie_o = mie & SUPERVISOR_INTERRUPT_MASK & mideleg;
    assign sip_o = mip_o & mideleg;
    assign satp_o = satp;

    always_comb begin
        csr_late_val_o = '0;
        case (csr_late_read_addr_i)
            MCYCLE, CYCLE : csr_late_val_o = mcycle;
            MINSTRET, INSTRET : csr_late_val_o = minstret;
            TIME : csr_late_val_o = time_i;
            default : ;
        endcase
    end

    always_comb begin
        // Even though the read port takes from csr_read_addr_i, the illegal read detection comes
        // from ctrl_i. This means that CSR values are read speculatively a couple cycles earlier
        // than we know whether they're legal.
        // We then assume, speculatively, that a read is valid. This can be potentially hazardous
        // for a memory write. In the current 5 stage pipeline, a memory write happens when the next
        // instruction is in WB. As a result, we will know for certain at that point whether we need
        // to flush the pipeline. However, if a store happens (ie past the point of no return) more
        // than one cycle before the CSR exception handling, a stall may be necessary.
        csr_illegal_inst_o = '0;
        csr_val_o = '0;

        // We want to handle the TVM, TW, and TSR bits here
        // TVM: S-mode reads/writes to satp or executes to SFENCE.VMA result in an illegal
        // instruction
        if (mstatus[MSTATUS_TVM] && machine_privilege == S_MODE &&
            (ctrl_i.tlb_invalidate ||
                ((ctrl_i.csr_write || ctrl_i.csr_read) && ctrl_i.csr_addr == SATP)))
        begin
            csr_illegal_inst_o = '1;
        end

        // TW: S/U executing WFI
        if (mstatus[MSTATUS_TW] && machine_privilege <= S_MODE && ctrl_i.wfi) begin
            csr_illegal_inst_o = '1;
        end

        // TSR: S executing SRET
        if (mstatus[MSTATUS_TSR] && machine_privilege == S_MODE && ctrl_i.sret) begin
            csr_illegal_inst_o = '1;
        end

        // Handle illegal CSR accesses
        // There are a few cases:
        //  1. Read/write to a CSR which does not exist
        //  2. Write to a read-only CSR
        //  3. Read/write to a CSR which is above the current privilege level
        if ((ctrl_i.csr_write || ctrl_i.csr_read) && !csr_exists) begin
            csr_illegal_inst_o = '1;
        end

        if (ctrl_i.csr_write && ctrl_i.csr_addr[11:10] == CSR_READ_ONLY) begin
            csr_illegal_inst_o = '1;
        end

        if ((ctrl_i.csr_write || ctrl_i.csr_read) && machine_privilege_t'(ctrl_i.csr_addr[9:8]) > machine_privilege) begin
            csr_illegal_inst_o = '1;
        end

        if ((ctrl_i.csr_write || ctrl_i.csr_read)
            && ctrl_i.csr_addr == STIMECMP
            && machine_privilege == S_MODE
            && !menvcfg[MENVCFG_STCE]) begin
            csr_illegal_inst_o = '1;
        end

        // Counter accesses should sometimes lead to errors based on the value of mcounteren
        if ((ctrl_i.csr_write || ctrl_i.csr_read) && machine_privilege < M_MODE) begin
            if ((ctrl_i.csr_addr == CYCLE && !mcounteren[COUNT_CY])
                || ((ctrl_i.csr_addr == TIME || ctrl_i.csr_addr == STIMECMP) && !mcounteren[COUNT_TM])
                || (ctrl_i.csr_addr == INSTRET && !mcounteren[COUNT_IR])
                || (ctrl_i.csr_addr >= HPMCOUNTER3 && ctrl_i.csr_addr <= HPMCOUNTER31 && !mcounteren[ctrl_i.csr_addr - MCYCLE])) begin
                    csr_illegal_inst_o = '1;
                end
        end

        // Counter accesses should sometimes lead to errors based on the value of scounteren
        if ((ctrl_i.csr_write || ctrl_i.csr_read) && machine_privilege < S_MODE) begin
            if ((ctrl_i.csr_addr == CYCLE && !scounteren[COUNT_CY])
                || ((ctrl_i.csr_addr == TIME || ctrl_i.csr_addr == STIMECMP) && !scounteren[COUNT_TM])
                || (ctrl_i.csr_addr == INSTRET && !scounteren[COUNT_IR])
                || (ctrl_i.csr_addr >= HPMCOUNTER3 && ctrl_i.csr_addr <= HPMCOUNTER31 && !scounteren[ctrl_i.csr_addr - MCYCLE])) begin
                    csr_illegal_inst_o = '1;
                end
        end

        if (csr_read_addr_i >= PMPCFG0 && csr_read_addr_i <= PMPCFG15 && !csr_read_addr_i[0]) begin
            for (int i = 0; i < PMP_ENTRIES_PER_CFG_CSR; i++) begin
                csr_val_o[8*i +: 8] = pmp_cfg[PMP_ENTRIES_PER_CFG_CSR * int'(pmpcfg_index) + i];
            end
        end else if (csr_read_addr_i >= PMPADDR0 && csr_read_addr_i <= PMPADDR63) begin
            csr_val_o = pmp_addr[pmpaddr_index];
        end else if ((csr_read_addr_i >= MHPMCOUNTER3 && csr_read_addr_i <= MHPMCOUNTER31)
                        || (csr_read_addr_i >= MHPMEVENT3 && csr_read_addr_i <= MHPMEVENT31)
                        || (csr_read_addr_i >= HPMCOUNTER3 && csr_read_addr_i <= HPMCOUNTER31)) begin
            csr_val_o = '0;
        end else begin
            case (csr_read_addr_i)
                MEPC : csr_val_o = mepc;
                MISA : csr_val_o = MISA_VAL;
                MVENDORID : csr_val_o = '0; // These values aren't implemented on this core
                MARCHID : csr_val_o = '0;
                MIMPID : csr_val_o = '0;
                MHARTID : csr_val_o = '0;   // This is a single core system (for now --- later I may want to parameterize)
                MCONFIGPTR : csr_val_o = '0;
                MSTATUS : csr_val_o = mstatus;
                MTVEC : csr_val_o = mtvec;
                MIE : csr_val_o = mie;
                // MTIP and STIP bits are hardwired
                MIP : csr_val_o = mip_o;
                MSCRATCH : csr_val_o = mscratch;
                MCAUSE : csr_val_o = mcause;
                MTVAL : csr_val_o = mtval;
                MENVCFG : csr_val_o = menvcfg;
                MSECCFG : csr_val_o = mseccfg;
                // FIOM is the sole implemented senvcfg bit.  It controls
                // U-mode, independently of menvcfg.FIOM's S/U-mode control.
                SENVCFG : csr_val_o = senvcfg;
                MCYCLE : csr_val_o = mcycle;
                MINSTRET : csr_val_o = minstret;
                MCOUNTEREN : csr_val_o = mcounteren;
                SCOUNTEREN : csr_val_o = scounteren;
                CYCLE : csr_val_o = mcycle;
                TIME : csr_val_o = time_i;
                INSTRET : csr_val_o = minstret;
                MCOUNTINHIBIT : csr_val_o = mcountinhibit;
                MIDELEG : csr_val_o = mideleg;
                MEDELEG : csr_val_o = medeleg;
                SSTATUS : csr_val_o = mstatus & SSTATUS_MASK;
                SIE : csr_val_o = sie_o;
                SSCRATCH : csr_val_o = sscratch;
                SEPC : csr_val_o = sepc;
                SCAUSE : csr_val_o = scause;
                STVAL : csr_val_o = stval;
                // Set a bit in SIP iff 
                SIP : csr_val_o = sip_o;
                STIMECMP : csr_val_o = stimecmp;
                STVEC : csr_val_o = stvec;
                SATP : csr_val_o = satp;
                default: csr_val_o = '0;
                // We can't use this assertion because sometimes transient states will result in a
                // read to an unimplemented register to appear like it is occurring very briefly.
                // // If we get here, something has gone wrong (ie we are either allowing a CSR address
                // // we shouldn't, or not all CSRs have been implemented)
                // default: $fatal(1, "CSR read CASE statement missing CSR: %h", ctrl_i.csr_addr);
            endcase
        end

        // We want to initiate a CSR flush if any of our speculations throughout the pipeline are no
        // longer correct:
        //  1. privilege changes
        //  2. mepc or sepc change
        //  3. mstatus changes
        //  4. satp changes
        //  5. sfence.vma being executed
        // Other things are handled elsewhere (eg PMPs by SFENCE.VMA, traps by wb_trap_redirect)
        csr_flush_o = '0;

        // mret/sret results in a privilege change and mepc/sepc change so we need a flush
        if (commit_i && (ctrl_i.mret || ctrl_i.sret)) begin
            csr_flush_o = '1;
        end else if (commit_i && ctrl_i.csr_write && !csr_illegal_inst_o) begin
            if (ctrl_i.csr_addr == MEPC) begin
                csr_flush_o = '1;
            end else if (ctrl_i.csr_addr == SEPC) begin
                csr_flush_o = '1;
            end else if (ctrl_i.csr_addr == MSTATUS) begin
                csr_flush_o = '1;
            end else if (ctrl_i.csr_addr == SATP) begin
                csr_flush_o = '1;
            end
        end else if (commit_i && ctrl_i.tlb_invalidate && !csr_illegal_inst_o) begin
            csr_flush_o = '1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            // Reset to machine mode
            machine_privilege <= M_MODE;
            mepc <= '0;
            mstatus <= MSTATUS_VAL;
            mtvec <= MVEC_VAL;
            mip <= XLEN'(32'h0000_0000);
            mie <= '0;
            mscratch <= '0;
            mcause <= '0;
            mtval <= '0;
            menvcfg <= '0;
            mseccfg <= '0;
            senvcfg <= '0;
            for (int i = 0; i <= 63; i++) begin
                pmp_cfg[i] <= '0;
                pmp_addr[i] <= '0;
            end
            mcycle <= '0;
            minstret <= '0;
            mcountinhibit <= '0;
            medeleg <= '0;
            mideleg <= '0;
            mcounteren <= '0;

            stimecmp <= '0;
            scounteren <= '0;
            sscratch <= '0;
            sepc <= '0;
            scause <= '0;
            stval <= '0;
            stvec <= '0;
            satp <= '0;
        end else begin
            if (trap_take_i && trap_i.is_trap) begin
                if (trap_i.dest_machine_privilege == M_MODE) begin
                    if (trap_i.is_interrupt)
                        mcause <= {1'b1, trap_i.interrupt_cause};
                    else
                        mcause <= {1'b0, trap_i.exception_cause};

                    mepc <= trap_i.pc;
                    mtval <= trap_i.tval;

                    // Save the previous machine privilege and MIE value
                    mstatus[MSTATUS_MPP_MSB : MSTATUS_MPP_LSB] <= machine_privilege;
                    mstatus[MSTATUS_MPIE] <= mstatus[MSTATUS_MIE];
                    // Disable interrupts
                    mstatus[MSTATUS_MIE] <= '0;
                    // Enter machine mode
                    machine_privilege <= M_MODE;
                end else if (trap_i.dest_machine_privilege == S_MODE) begin
                    if (trap_i.is_interrupt)
                        scause <= {1'b1, trap_i.interrupt_cause};
                    else
                        scause <= {1'b0, trap_i.exception_cause};

                    sepc <= trap_i.pc;
                    stval <= trap_i.tval;

                    // Save the previous machine privilege and MIE value
                    mstatus[MSTATUS_SPP] <= machine_privilege[0];
                    mstatus[MSTATUS_SPIE] <= mstatus[MSTATUS_SIE];
                    // Disable interrupts
                    mstatus[MSTATUS_SIE] <= '0;
                    // Enter supervisor mode
                    machine_privilege <= S_MODE;
                end
            end else if (commit_i && ctrl_i.mret) begin
                // Revert to previous privilege (before trap)
                machine_privilege <= machine_privilege_t'(mstatus[MSTATUS_MPP_MSB : MSTATUS_MPP_LSB]);
                // Revert to previous interrupt enable bit
                mstatus[MSTATUS_MIE] <= mstatus[MSTATUS_MPIE];
                mstatus[MSTATUS_MPIE] <= '1;
                // Update MPP to least supported mode (user)
                mstatus[MSTATUS_MPP_MSB : MSTATUS_MPP_LSB] <= U_MODE;

                // Turn off MPRV if the new privilege != M
                if (machine_privilege_t'(mstatus[MSTATUS_MPP_MSB : MSTATUS_MPP_LSB]) != M_MODE)
                    mstatus[MSTATUS_MPRV] <= '0;
            end else if (commit_i && ctrl_i.sret) begin
                // Revert to previous privilege (before trap)
                machine_privilege <= machine_privilege_t'({1'b0, mstatus[MSTATUS_SPP]});
                // Revert to previous interrupt enable bit
                mstatus[MSTATUS_SIE] <= mstatus[MSTATUS_SPIE];
                mstatus[MSTATUS_SPIE] <= '1;
                // Update SPP to least supported mode (user)
                mstatus[MSTATUS_SPP] <= '0;

                // Turn off MPRV if the new privilege != M (always true)
                mstatus[MSTATUS_MPRV] <= '0;
            end else if (commit_i && ctrl_i.csr_write && !csr_illegal_inst_o) begin
                if (ctrl_i.csr_addr >= PMPCFG0 && ctrl_i.csr_addr <= PMPCFG15 && !ctrl_i.csr_addr[0]) begin
                    for (int i = 0; i < PMP_ENTRIES_PER_CFG_CSR; i++) begin
                        if (!pmp_cfg[PMP_ENTRIES_PER_CFG_CSR * int'(pmpcfg_index) + i][PMPCFG_L_IDX]) begin
                            pmp_cfg[PMP_ENTRIES_PER_CFG_CSR * int'(pmpcfg_index) + i] <=
                                csr_data_i[8*i +: 8]
                                & ((csr_data_i[8*i + PMPCFG_W_IDX]
                                    && !csr_data_i[8*i + PMPCFG_R_IDX]) ? 8'hfd : 8'hff);
                        end
                    end
                end else if (ctrl_i.csr_addr >= PMPADDR0 && ctrl_i.csr_addr <= PMPADDR63) begin
                    if (!pmp_cfg[pmpaddr_index][PMPCFG_L_IDX]) begin
                        if (pmpaddr_index == 6'd63) begin
                            pmp_addr[pmpaddr_index] <= {{(XLEN - PMP_ADDR_WIDTH){1'b0}}, csr_data_i[PMP_ADDR_WIDTH-1:0]};
                        end else if (!pmp_cfg[pmpaddr_index + 1'b1][PMPCFG_L_IDX]
                                     || pmp_addr_matching_t'(pmp_cfg[pmpaddr_index + 1'b1][PMPCFG_A_MSB:PMPCFG_A_LSB]) != PMP_TOR) begin
                            pmp_addr[pmpaddr_index] <= {{(XLEN - PMP_ADDR_WIDTH){1'b0}}, csr_data_i[PMP_ADDR_WIDTH-1:0]};
                        end
                    end
                end else if ((ctrl_i.csr_addr >= MHPMCOUNTER3 && ctrl_i.csr_addr <= MHPMCOUNTER31)
                             || (ctrl_i.csr_addr >= MHPMEVENT3 && ctrl_i.csr_addr <= MHPMEVENT31)) begin
                    // Unimplemented HPM counters and event selectors are writable no-ops.
                end else begin
                case (ctrl_i.csr_addr)
                    MEPC : mepc <= legalize_csr_write(MEPC, csr_data_i, mepc);
                    MISA : ;    // misa is effectively unwritable because the ISA does not change.
                    MSTATUS : mstatus <= legalize_csr_write(MSTATUS, csr_data_i, mstatus);
                    MTVEC : mtvec <= legalize_csr_write(MTVEC, csr_data_i, mtvec);
                    MIE : mie <= legalize_csr_write(MIE, csr_data_i, mie);
                    MIP : mip <= legalize_csr_write(MIP, csr_data_i, mip);
                    MSCRATCH : mscratch <= csr_data_i;
                    MCAUSE : mcause <= legalize_csr_write(MCAUSE, csr_data_i, mcause);
                    MTVAL : mtval <= csr_data_i;
                    MENVCFG : menvcfg <= legalize_csr_write(MENVCFG, csr_data_i, menvcfg);
                    MSECCFG : mseccfg <= legalize_csr_write(MSECCFG, csr_data_i, mseccfg);
                    SENVCFG : senvcfg <= legalize_csr_write(SENVCFG, csr_data_i, senvcfg);
                    MCYCLE : mcycle <= csr_data_i;
                    MINSTRET : minstret <= csr_data_i;
                    MCOUNTINHIBIT : mcountinhibit <= legalize_csr_write(MCOUNTINHIBIT, csr_data_i, mcountinhibit);
                    MEDELEG : medeleg <= legalize_csr_write(MEDELEG /* logic[11:0] */, csr_data_i /* logic[63:0] */, medeleg /* logic[63:0] */);
                    MIDELEG : mideleg <= legalize_csr_write(MIDELEG /* logic[11:0] */, csr_data_i /* logic[63:0] */, mideleg /* logic[63:0] */);
                    MCOUNTEREN : mcounteren <= csr_data_i & XLEN'(3'b111);
                    SCOUNTEREN : scounteren <= csr_data_i & XLEN'(3'b111);
                    SSTATUS : mstatus <= legalize_csr_write(SSTATUS, csr_data_i /* logic[63:0] */, mstatus /* logic[63:0] */);
                    SIP : mip <= legalize_csr_write(SIP, csr_data_i /* logic[63:0] */, mip /* logic[63:0] */);
                    SIE : mie <= legalize_csr_write(SIE, csr_data_i /* logic[63:0] */, mie /* logic[63:0] */);
                    SSCRATCH : sscratch <= csr_data_i;
                    SEPC : sepc <= legalize_csr_write(SEPC, csr_data_i, sepc);
                    SCAUSE : scause <= csr_data_i;
                    STVAL : stval <= csr_data_i;
                    STIMECMP : stimecmp <= csr_data_i;
                    STVEC : stvec <= legalize_csr_write(STVEC, csr_data_i, stvec);
                    SATP : satp <= legalize_csr_write(SATP, csr_data_i, satp);
                    // If we get here, something has gone wrong (ie we are either allowing a CSR address
                    // we shouldn't, or not all CSRs have been implemented)
                    default: $fatal(1, "CSR write CASE statement missing CSR: %h", ctrl_i.csr_addr);
                endcase
                end
            end

            // Increment cycle counter and instruction count ONLY if it wasn't written by a CSR
            // operation. mcountinhibit should also not be set. So both these conditions must be met
            if (!mcountinhibit[COUNT_CY] && (!ctrl_i.csr_write || csr_illegal_inst_o || ctrl_i.csr_addr != MCYCLE || !commit_i))
                mcycle <= mcycle + XLEN'(cycle_tick_i);
            if (!mcountinhibit[COUNT_IR] && (!ctrl_i.csr_write || csr_illegal_inst_o || ctrl_i.csr_addr != MINSTRET || !commit_i))
            minstret <= minstret + XLEN'(retire_count_i);
        end
    end

function automatic logic csr_addr_exists(
    input logic [11:0] csr_addr
);
    return (csr_addr >= MVENDORID && csr_addr <= MCONFIGPTR)
        || csr_addr == MSTATUS || csr_addr == MISA || csr_addr == MEDELEG || csr_addr == MIDELEG
        || csr_addr == MIE || csr_addr == MTVEC || csr_addr == MCOUNTEREN || csr_addr == MENVCFG
        || (csr_addr >= MSCRATCH && csr_addr <= MIP)
        || csr_addr == MSECCFG
        || (csr_addr >= PMPCFG0 && csr_addr <= PMPCFG15 && !csr_addr[0])    // only even PMPCFGs are allowed in RV64
        || (csr_addr >= PMPADDR0 && csr_addr <= PMPADDR63)
        || csr_addr == MCYCLE || csr_addr == MINSTRET
        || csr_addr == CYCLE || csr_addr == TIME || csr_addr == INSTRET
        || (csr_addr >= HPMCOUNTER3 && csr_addr <= HPMCOUNTER31)
        || (csr_addr >= MHPMCOUNTER3 && csr_addr <= MHPMCOUNTER31)
        || (csr_addr >= MHPMEVENT3 && csr_addr <= MHPMEVENT31)
        || csr_addr == MCOUNTINHIBIT
        || csr_addr == SSTATUS || csr_addr == SIE || csr_addr == STVEC || csr_addr == SENVCFG
        || csr_addr == SCOUNTEREN || csr_addr == SSCRATCH || csr_addr == SEPC
        || csr_addr == SCAUSE || csr_addr == STVAL || csr_addr == SIP
        || csr_addr == STIMECMP || csr_addr == SATP;
endfunction

function automatic logic [XLEN-1:0] legalize_csr_write(
    input logic [11:0] csr_addr,
    input logic [XLEN-1:0] value,
    input logic [XLEN-1:0] prev_val
);
    case (csr_addr)
        // MEPC[1:0] cannot take any value other than 'b00
        MEPC : legalize_csr_write = value & ~(XLEN'('d3));
        MSTATUS : begin
            legalize_csr_write = (value & MSTATUS_WRITE_MASK_VAL) | (prev_val & ~MSTATUS_WRITE_MASK_VAL);
            if (machine_privilege_t'(value[MSTATUS_MPP_MSB : MSTATUS_MPP_LSB]) == RESERVED) begin
                legalize_csr_write[MSTATUS_MPP_MSB : MSTATUS_MPP_LSB] = M_MODE;
            end
        end
        MTVEC : begin
            legalize_csr_write = value;
            // bits 1:0 (MODE) must be set to 0 (direct) or 1 (vectored)
            if (legalize_csr_write[1:0] > 'b01) begin
                legalize_csr_write[1:0] = TRAP_DIRECT;
            end
        end
        // MIP is driven by interrupt sources, with a couple exceptions:
        // - SEIP
        // - SSIP
        // So these two bits are writable
        MIP : legalize_csr_write = value & (MIP_WRITABLE_MASK
                             | (!menvcfg[MENVCFG_STCE] ? (XLEN'(1) << S_TIMER) : '0));
        MIE : legalize_csr_write = value & STANDARD_INTERRUPT_MASK;
        // Implement the standard delegatable synchronous exceptions and all
        // six standard supervisor/machine interrupt causes.  ECALL-from-M
        // (bit 11) and ECALL-from-S (bit 9) cannot be delegated downward.
        MIDELEG : legalize_csr_write = value & SUPERVISOR_INTERRUPT_MASK;
        MEDELEG : legalize_csr_write = value & MEDELEG_WRITABLE_MASK;
        MCAUSE : begin
            // Previously, I didn't allow writes of reserved values. However, the RISC-V Sail model
            // expects these to be allowed, which is technically valid under the ISA.
            legalize_csr_write = value;
        end
        // FIOM and Sstc.STCE are writable; unsupported menvcfg bits remain zero.
        MENVCFG : legalize_csr_write = (value & MENVCFG_WRITABLE_MASK)
                         | (prev_val & ~MENVCFG_WRITABLE_MASK);
        // FIOM is the sole implemented senvcfg field.
        SENVCFG : legalize_csr_write = (value & 'b1) | (prev_val & (~'b1));
        // no bits can be written
        MSECCFG : legalize_csr_write = (value & 'b0) | (prev_val & (~'b0));
        // bit 1 cannot be set to anything other than 0, bits 3-63 are read only
        MCOUNTINHIBIT : legalize_csr_write = value & ((XLEN'(1) << COUNT_CY)
                                                     | (XLEN'(1) << COUNT_IR));
        SSTATUS : legalize_csr_write = (value & SSTATUS_WRITE_MASK)
                                     | (prev_val & (~SSTATUS_WRITE_MASK));
        SIE : legalize_csr_write = (value & SUPERVISOR_INTERRUPT_MASK & mideleg) | (prev_val & (~(SUPERVISOR_INTERRUPT_MASK & mideleg)));
        // SSIP is the only supervisor pending bit this implementation lets
        // software raise or clear.  As a supervisor CSR view, it is writable
        // only after M-mode delegates that interrupt class.
        SIP : legalize_csr_write = (value & (XLEN'(1) << S_SOFTWARE) & mideleg)
                    | (prev_val & ~((XLEN'(1) << S_SOFTWARE) & mideleg));
        SEPC : legalize_csr_write = value & ~(XLEN'('d3));
        STVEC : begin
            legalize_csr_write = value;
            // bits 1:0 (MODE) must be set to 0 (direct) or 1 (vectored)
            if (legalize_csr_write[1:0] > 'b01) begin
                legalize_csr_write[1:0] = TRAP_DIRECT;
            end
        end
        SATP : begin
            case (satp_mode_t'(value[SATP_MODE_MSB : SATP_MODE_LSB]))
                // With MODE_BARE, the rest of the fields are zero'd (no virtual memory)
                MODE_BARE : legalize_csr_write = '0;
                MODE_SV39 : legalize_csr_write = value;
                default : legalize_csr_write = '0;
            endcase
        end
        default: legalize_csr_write = value;
    endcase
endfunction
endmodule : csrfile
