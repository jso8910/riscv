import riscv::*;

module csrfile (
    input logic                  clk,
    input logic                  rst_n,
    input ctrl_t                 ctrl_i,
    input logic                  cycle_tick_i,
    // NOTE: for now, retire_count can only equal 0 or 1 because we don't have a superscalar processor.
    input logic                  retire_count_i,
    input logic [XLEN-1:0]       rs1_i,
    input trap_t                 trap_i,
    output logic [XLEN-1:0]      csr_val_o,
    output logic [XLEN-1:0]      mepc_o,
    output logic [XLEN-1:0]      mtvec_o,
    output logic                 csr_illegal_inst_o,
    output machine_privilege_t   machine_privilege_o
);
    localparam int PMP_ENTRIES_PER_CFG_CSR = XLEN / 8;

    // CSR register definitions
    logic [XLEN-1:0] mepc, mstatus, mstatush, mtvec, mip, mie, mscratch, mcause,
                     mtval, menvcfg, menvcfgh, mseccfg, mseccfgh, mcycle, mcycleh,
                     minstret, minstreth, mcountinhibit;

    logic [63:0] mcycle_full, minstret_full;

    // physical memory protection CSRs
    pmp_entry_t pmp_entries [0:63];

    // Some internal signals
    logic [XLEN-1:0] value_to_write;
    logic [XLEN-1:0] rs1_uimm_chosen;
    logic            csr_exists;
    logic [3:0]      pmpcfg_index;
    logic [5:0]      pmpaddr_index;

    // Current privilege level
    machine_privilege_t machine_privilege;

    // We want to either 0 extend a 5 bit immediate (stored in the rs1 address field) or take the
    // value of rs1
    assign rs1_uimm_chosen = ctrl_i.csr_imm ? {(XLEN-5)'(1'b0), ctrl_i.rs1_addr} : rs1_i;

    assign csr_exists = csr_addr_exists(ctrl_i.csr_addr);
    assign pmpcfg_index = ctrl_i.csr_addr[3:0] - PMPCFG0[3:0];
    assign pmpaddr_index = ctrl_i.csr_addr[5:0] - PMPADDR0[5:0];

    assign {mcycleh, mcycle} = mcycle_full;
    assign {minstreth, minstret} = minstret_full;

    assign mepc_o = mepc;
    assign mtvec_o = mtvec;
    assign machine_privilege_o = machine_privilege;

    always_comb begin
        csr_illegal_inst_o = '0;
        csr_val_o = '0;

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

        if (ctrl_i.csr_read && !csr_illegal_inst_o) begin
            case (ctrl_i.csr_addr) inside
                MEPC : csr_val_o = mepc;
                MISA : csr_val_o = MISA_VAL;
                MVENDORID : csr_val_o = '0; // These values aren't implemented on this core
                MARCHID : csr_val_o = '0;
                MIMPID : csr_val_o = '0;
                MHARTID : csr_val_o = '0;   // This is a single core system (for now --- later I may want to parameterize)
                MCONFIGPTR : csr_val_o = '0;
                MSTATUS : csr_val_o = mstatus;
                MSTATUSH : csr_val_o = mstatush;
                MTVEC : csr_val_o = mtvec;
                MIE : csr_val_o = mie;
                MIP : csr_val_o = mip;
                MSCRATCH : csr_val_o = mscratch;
                MCAUSE : csr_val_o = mcause;
                MTVAL : csr_val_o = mtval;
                MENVCFG : csr_val_o = menvcfg;
                MENVCFGH : csr_val_o = menvcfgh;
                MSECCFG : csr_val_o = mseccfg;
                MSECCFGH : csr_val_o = mseccfgh;
                [PMPCFG0:PMPCFG15] : begin
                    for (int i = 0; i < PMP_ENTRIES_PER_CFG_CSR; i++) begin
                        csr_val_o[8*i +: 8] = pmp_entries[PMP_ENTRIES_PER_CFG_CSR * int'(pmpcfg_index) + i].cfg;
                    end
                end
                [PMPADDR0:PMPADDR63] : csr_val_o = pmp_entries[pmpaddr_index].addr;
                MCYCLE : csr_val_o = mcycle;
                MCYCLEH : csr_val_o = mcycleh;
                MINSTRET : csr_val_o = minstret;
                MINSTRETH : csr_val_o = minstreth;
                // These counters are not implemented
                [MHPMCOUNTER3:MHPMCOUNTER31] : csr_val_o = '0;
                [MHPMCOUNTER3H:MHPMCOUNTER31H] : csr_val_o = '0;
                [MHPMEVENT3:MHPMEVENT31] : csr_val_o = '0;
                [MHPMEVENT3H:MHPMEVENT31H] : csr_val_o = '0;
                MCOUNTINHIBIT : csr_val_o = mcountinhibit;
                // If we get here, something has gone wrong (ie we are either allowing a CSR address
                // we shouldn't, or not all CSRs have been implemented)
                default: $fatal(1, "CSR read CASE statement missing CSR: %h", ctrl_i.csr_addr);
            endcase
        end

        // Set value to write
        case (ctrl_i.csr_wb_sel)
            WB_NORMAL : value_to_write = rs1_uimm_chosen;
            WB_SET_BITS : value_to_write = csr_val_o | rs1_uimm_chosen;
            WB_CLEAR_BITS : value_to_write = csr_val_o & (~rs1_uimm_chosen);
            default : value_to_write = '0;
        endcase    
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            // Reset to machine mode
            machine_privilege <= M_MODE;
            mepc <= '0;
            mstatus <= MSTATUS_VAL;
            mstatush <= MSTATUSH_VAL;
            mtvec <= MVEC_VAL;
            mip <= '0;
            mie <= '0;
            mscratch <= '0;
            mcause <= '0;
            mtval <= '0;
            menvcfg <= '0;
            menvcfgh <= '0;
            mseccfg <= '0;
            mseccfgh <= '0;
            for (int i = 0; i <= 63; i++) begin
                pmp_entries[i] <= '0;
            end
            mcycle_full <= '0;
            minstret_full <= '0;
            mcountinhibit <= '0;
        end else begin
            if (trap_i.is_trap) begin
                // TODO remember to use mideleg/medeleg to decide whether we instead trap into
                // supervisor
                mepc <= trap_i.pc;
                mtval <= trap_i.tval;

                if (trap_i.is_interrupt)
                    mcause <= {1'b1, trap_i.interrupt_cause};
                else
                    mcause <= {1'b0, trap_i.exception_cause};

                // Save the previous machine privilege and MIE value
                mstatus[MSTATUS_MPP_MSB : MSTATUS_MPP_LSB] <= machine_privilege;
                mstatus[MSTATUS_MPIE] <= mstatus[MSTATUS_MIE];
                // Disable interrupts
                mstatus[MSTATUS_MIE] <= '0;
                // Enter machine mode (later support for mideleg/medeleg TODO)
                machine_privilege <= M_MODE;
            end else if (ctrl_i.mret) begin
                // TODO add check that we are actually in machine mode
                // Revert to previous privilege (before trap)
                machine_privilege <= machine_privilege_t'(mstatus[MSTATUS_MPP_MSB : MSTATUS_MPP_LSB]);
                // Revert to previous interrupt enable bit
                mstatus[MSTATUS_MIE] <= mstatus[MSTATUS_MPIE];
                mstatus[MSTATUS_MPIE] <= '1;
                // TODO: change to least privileged mode
                mstatus[MSTATUS_MPP_MSB : MSTATUS_MPP_LSB] <= M_MODE;

                // Turn off MPRV if the new privilege != M
                if (machine_privilege_t'(mstatus[MSTATUS_MPP_MSB : MSTATUS_MPP_LSB]) != M_MODE)
                    mstatus[MSTATUS_MPRV] <= '0;
            end else if (ctrl_i.csr_write && !csr_illegal_inst_o) begin
                case (ctrl_i.csr_addr) inside
                    MEPC : mepc <= legalize_csr_write(MEPC, value_to_write, mepc);
                    MISA : ;    // misa is effectively unwritable because the ISA does not change.
                    MSTATUS : mstatus <= legalize_csr_write(MSTATUS, value_to_write, mstatus);
                    MSTATUSH : mstatush <= legalize_csr_write(MSTATUSH, value_to_write, mstatush);
                    MTVEC : mtvec <= legalize_csr_write(MTVEC, value_to_write, mtvec);
                    MIE : mie <= legalize_csr_write(MIE, value_to_write, mie);
                    MIP : mip <= legalize_csr_write(MIP, value_to_write, mip);
                    MSCRATCH : mscratch <= value_to_write;
                    MCAUSE : mcause <= legalize_csr_write(MCAUSE, value_to_write, mcause);
                    MTVAL : mtval <= value_to_write;
                    MENVCFG : menvcfg <= legalize_csr_write(MENVCFG, value_to_write, menvcfg);
                    MENVCFGH : menvcfgh <= legalize_csr_write(MENVCFGH, value_to_write, menvcfgh);
                    MSECCFG : mseccfg <= legalize_csr_write(MSECCFG, value_to_write, mseccfg);
                    MSECCFGH : mseccfgh <= legalize_csr_write(MSECCFGH, value_to_write, mseccfgh);
                    [PMPCFG0:PMPCFG15] : begin
                        for (int i = 0; i < PMP_ENTRIES_PER_CFG_CSR; i++) begin
                            if (!pmp_entries[PMP_ENTRIES_PER_CFG_CSR * int'(pmpcfg_index) + i].cfg[PMPCFG_L_IDX]) begin
                                // This case (R = 0, W = 1) is reserved. Fallback to R = 0, W = 0.
                                pmp_entries[PMP_ENTRIES_PER_CFG_CSR * int'(pmpcfg_index) + i].cfg <=
                                    value_to_write[8*i +: 8]
                                    & ((value_to_write[8*i + PMPCFG_W_IDX]
                                        && !value_to_write[8*i + PMPCFG_R_IDX]) ? 8'hfd : 8'hff);
                            end
                        end
                    end
                    [PMPADDR0:PMPADDR63] : begin
                        if (!pmp_entries[pmpaddr_index].cfg[PMPCFG_L_IDX]) begin
                            if (pmpaddr_index == 6'd63) begin
                                pmp_entries[pmpaddr_index].addr <= value_to_write;
                            end else if (!pmp_entries[pmpaddr_index + 1'b1].cfg[PMPCFG_L_IDX]
                                         || pmp_addr_matching_t'(pmp_entries[pmpaddr_index + 1'b1].cfg[PMPCFG_A_MSB:PMPCFG_A_LSB]) != PMP_TOR) begin
                                pmp_entries[pmpaddr_index].addr <= value_to_write;
                            end
                        end
                    end
                    MCYCLE : mcycle_full[31:0] <= value_to_write;
                    MCYCLEH : mcycle_full[63:32] <= value_to_write;
                    MINSTRET : minstret_full[31:0] <= value_to_write;
                    MINSTRETH : minstret_full[63:32] <= value_to_write;
                    [MHPMCOUNTER3:MHPMCOUNTER31] : ;
                    [MHPMCOUNTER3H:MHPMCOUNTER31H] : ;
                    [MHPMEVENT3:MHPMEVENT31] : ;
                    [MHPMEVENT3H:MHPMEVENT31H] : ;
                    MCOUNTINHIBIT : mcountinhibit <= legalize_csr_write(MCOUNTINHIBIT, value_to_write, mcountinhibit);
                    // If we get here, something has gone wrong (ie we are either allowing a CSR address
                    // we shouldn't, or not all CSRs have been implemented)
                    default: $fatal(1, "CSR write CASE statement missing CSR: %h", ctrl_i.csr_addr);
                endcase
            end

            // Increment cycle counter and instruction count ONLY if it wasn't written by a CSR
            // operation. mcountinhibit should also not be set. So both these conditions must be met
            if (!mcountinhibit[MCOUNTINHIBIT_CY] && (!ctrl_i.csr_write || csr_illegal_inst_o || !(ctrl_i.csr_addr inside {MCYCLE, MCYCLEH})))
                mcycle_full <= mcycle_full + 64'(cycle_tick_i);
            if (!mcountinhibit[MCOUNTINHIBIT_IR] && (!ctrl_i.csr_write || csr_illegal_inst_o || !(ctrl_i.csr_addr inside {MINSTRET, MINSTRETH})))
            minstret_full <= minstret_full + 64'(retire_count_i);
        end
    end

function automatic logic csr_addr_exists(
    input logic [11:0] csr_addr
);
    return csr_addr inside {
        [MVENDORID:MCONFIGPTR],
        MSTATUS,
        MISA,
        MIE,
        MTVEC,
        MENVCFG,
        MSTATUSH,
        MENVCFGH,
        [MSCRATCH:MIP],
        MSECCFG,
        MSECCFGH,
        [PMPCFG0:PMPCFG15],
        [PMPADDR0:PMPADDR63],
        MCYCLE,
        MCYCLEH,
        MINSTRET,
        MINSTRETH,
        [MHPMCOUNTER3:MHPMCOUNTER31],
        [MHPMCOUNTER3H:MHPMCOUNTER31H],
        [MHPMEVENT3:MHPMEVENT31],
        [MHPMEVENT3H:MHPMEVENT31H],
        MCOUNTINHIBIT
    };
endfunction

function automatic logic [XLEN-1:0] legalize_csr_write(
    input logic [11:0] csr_addr,
    input logic [XLEN-1:0] value,
    input logic [XLEN-1:0] prev_val
);
    case (csr_addr) inside
        // MEPC[1:0] cannot take any value other than 'b00
        MEPC : legalize_csr_write = value & 32'hFFFF_FFFC;
        MSTATUS : begin
            legalize_csr_write = (value & MSTATUS_WRITE_MASK_VAL) | (prev_val & ~MSTATUS_WRITE_MASK_VAL);
            if (machine_privilege_t'(legalize_csr_write[MSTATUS_MPP_MSB : MSTATUS_MPP_LSB]) != IMPLEMENTED_PRIVILEGES[0]) begin
                legalize_csr_write[MSTATUS_MPP_MSB : MSTATUS_MPP_LSB] = IMPLEMENTED_PRIVILEGES[0];
            end
        end
        MSTATUSH : begin
            legalize_csr_write = (value & MSTATUSH_WRITE_MASK_VAL) | (prev_val & ~MSTATUSH_WRITE_MASK_VAL);
        end
        MTVEC : begin
            legalize_csr_write = value;
            // bits 1:0 (MODE) must be set to 0 (direct) or 1 (vectored)
            if (legalize_csr_write[1:0] > 'b01) begin
                legalize_csr_write[1:0] = TRAP_DIRECT;
            end
        end
        // Bits 31:16 are for platform-specific interrupts (none implemented). Otherwise, these
        // masked interrupts can become pending and thus can be written.
        // Interrupts are cleared by writing 0 to MIP at bit i.
        MIP : legalize_csr_write = value & ('b0010_1010_1010_1010);
        MIE : legalize_csr_write = value & ('b0010_1010_1010_1010);
        MCAUSE : begin
            legalize_csr_write = value;
            // There are different sets of legal values depending on the bit at XLEN-1
            if (legalize_csr_write[XLEN-1]) begin     // interrupt mode
                if (!(legalize_csr_write[XLEN-2:0] inside {1, 3, 5, 7, 9, 11, 13})) begin
                    // TODO: is this a good default value?
                    // Sets mcause to 0 if a reserved value was used by the software manual write
                    legalize_csr_write = '0;
                end
            end else begin                             // Normal errors
                if (legalize_csr_write[XLEN-2:0] inside {10, 14, 17} || legalize_csr_write[XLEN-2:0] >= 20) begin
                    legalize_csr_write = '0;
                end
            end
        end
        // only bit 0 can be written
        MENVCFG : legalize_csr_write = (value & 'b1) | (prev_val & (~'b1));
        // no bits can be written
        MENVCFGH : legalize_csr_write = (value & 'b0) | (prev_val & (~'b0));
        // no bits can be written
        MSECCFG : legalize_csr_write = (value & 'b0) | (prev_val & (~'b0));
        // no bits can be written
        MSECCFGH : legalize_csr_write = (value & 'b0) | (prev_val & (~'b0));
        // bit 1 cannot be set to anything other than 0, bits 3-31 are read only
        MCOUNTINHIBIT : legalize_csr_write = value & ('b101);
        default: legalize_csr_write = value;
    endcase
endfunction
endmodule : csrfile
