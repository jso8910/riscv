import riscv::*;

module control_unit (
    input logic [IALIGN-1:0]  inst_i,
    input machine_privilege_t current_privilege_i,
    output logic [XLEN-1:0]   imm_o,
    output ctrl_t             ctrl_o
);

    // =========================
    // Static instruction fields
    // =========================

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;

    assign opcode = inst_i[OPCODE_MSB : OPCODE_LSB];
    assign funct3 = inst_i[FUNCT3_MSB : FUNCT3_LSB];
    assign funct7 = inst_i[FUNCT7_MSB : FUNCT7_LSB];

    // Immediate generation module
    immediate_gen u_immediate_gen (
        .inst_i        (inst_i),
        .inst_fmt_i    (ctrl_o.inst_fmt),
        .imm_o         (imm_o)
    );

    always_comb begin
        ctrl_o = '0;

        ctrl_o.op1_src = RS1;

        ctrl_o.rs1_addr = inst_i[RS1_MSB : RS1_LSB];
        ctrl_o.rs2_addr = inst_i[RS2_MSB : RS2_LSB];
        ctrl_o.rd_addr = inst_i[RD_MSB : RD_LSB];

        // By default (for LOAD/STORE/JAL/JALR/B) we want the ALU to output rs1 + imm
        ctrl_o.alu_op = ALU_ADD;
        ctrl_o.alu_sel_imm = '1;
        ctrl_o.alu_word_op = '0;

        ctrl_o.branch = '0;
        ctrl_o.branch_cond = COND_EQ;
        ctrl_o.jal = '0;
        ctrl_o.jalr = '0;
        ctrl_o.branch_src = SRC_ALU;

        ctrl_o.mem_read = '0;
        ctrl_o.mem_write = '0;
        ctrl_o.mem_size = MEM_NONE;
        ctrl_o.mem_signed = MEM_SIGNED;

        ctrl_o.wb_sel = WB_IMM;
        ctrl_o.reg_write = '0;

        ctrl_o.csr_write = '0;
        ctrl_o.csr_read = '0;
        ctrl_o.csr_addr = inst_i[31:20];
        ctrl_o.csr_wb_sel = WB_NORMAL;
        ctrl_o.csr_imm = '0;

        ctrl_o.ebreak = '0;
        ctrl_o.ecall = '0;
        ctrl_o.mret = '0;

        ctrl_o.illegal = '0;

        case (opcode)
            LUI : begin
                ctrl_o.inst_fmt = IMM_U;

                ctrl_o.wb_sel = WB_IMM;
                ctrl_o.reg_write = '1;
            end
            AUIPC : begin
                ctrl_o.inst_fmt = IMM_U;

                ctrl_o.op1_src = PC;

                ctrl_o.wb_sel = WB_ALU;
                ctrl_o.reg_write = '1;
            end
            JAL : begin
                ctrl_o.inst_fmt = IMM_J;

                ctrl_o.op1_src = PC;

                ctrl_o.jal = '1;

                ctrl_o.wb_sel = WB_PC_PLUS_4;
                ctrl_o.reg_write = '1;
            end
            JALR : begin
                if (funct3 != 3'b000) ctrl_o.illegal = '1;
                ctrl_o.inst_fmt = IMM_I;

                ctrl_o.jalr = '1;

                ctrl_o.wb_sel = WB_PC_PLUS_4;
                ctrl_o.reg_write = '1;
            end
            BRANCH : begin
                ctrl_o.inst_fmt = IMM_B;

                ctrl_o.op1_src = PC;

                case (funct3)
                    EQ : ctrl_o.branch_cond = COND_EQ;
                    NE : ctrl_o.branch_cond = COND_NE;
                    LT : ctrl_o.branch_cond = COND_LT;
                    GE : ctrl_o.branch_cond = COND_GE;
                    LTU : ctrl_o.branch_cond = COND_LTU;
                    GEU : ctrl_o.branch_cond = COND_GEU;
                    default : ctrl_o.illegal = '1;
                endcase

                ctrl_o.branch = '1;
            end
            LOAD : begin
                ctrl_o.inst_fmt = IMM_I;

                ctrl_o.mem_read = '1;

                case (funct3)
                    LB : ctrl_o.mem_size = MEM_BYTE;
                    LH : ctrl_o.mem_size = MEM_HALF;
                    LW : ctrl_o.mem_size = MEM_WORD;
                    LD : ctrl_o.mem_size = MEM_DOUBLE;
                    LBU : begin
                        ctrl_o.mem_size = MEM_BYTE;
                        ctrl_o.mem_signed = MEM_UNSIGNED;
                    end
                    LHU : begin
                        ctrl_o.mem_size = MEM_HALF;
                        ctrl_o.mem_signed = MEM_UNSIGNED;
                    end
                    LWU : begin
                        ctrl_o.mem_size = MEM_WORD;
                        ctrl_o.mem_signed = MEM_UNSIGNED;
                    end
                    default : ctrl_o.illegal = '1;
                endcase

                ctrl_o.wb_sel = WB_MEM;
                ctrl_o.reg_write = '1;
            end
            STORE : begin
                ctrl_o.inst_fmt = IMM_S;

                ctrl_o.mem_write = '1;

                case (funct3)
                    SB : ctrl_o.mem_size = MEM_BYTE;
                    SH : ctrl_o.mem_size = MEM_HALF;
                    SW : ctrl_o.mem_size = MEM_WORD;
                    SD : ctrl_o.mem_size = MEM_DOUBLE;
                    default : ctrl_o.illegal = '1;
                endcase
            end
            OP_IMM, OP, OP_IMM_WORD, OP_WORD: begin
                ctrl_o.inst_fmt = IMM_R;
                ctrl_o.alu_sel_imm = '0;
                if (opcode == OP_IMM || opcode == OP_IMM_WORD) begin
                    ctrl_o.alu_sel_imm = '1;
                    ctrl_o.inst_fmt = IMM_I;
                end

                if (opcode == OP_IMM_WORD || opcode == OP_WORD) begin
                    ctrl_o.alu_word_op = '1;
                end

                casez ({funct3, funct7, ctrl_o.alu_sel_imm, ctrl_o.alu_word_op})
                    // Add/sub
                    {ADD_SUB, FUNCT7_ANY, 1'b1, 1'b?} : ctrl_o.alu_op = ALU_ADD;
                    {ADD_SUB, FUNCT7_BASE, 1'b0, 1'b?} : ctrl_o.alu_op = ALU_ADD;
                    {ADD_SUB, FUNCT7_ALT, 1'b0, 1'b?} : ctrl_o.alu_op = ALU_SUB;

                    // I-type
                    {SLT, FUNCT7_ANY, 1'b1, 1'b?} : ctrl_o.alu_op = ALU_SLT;
                    {SLTU, FUNCT7_ANY, 1'b1, 1'b?} : ctrl_o.alu_op = ALU_SLTU;
                    {XOR, FUNCT7_ANY, 1'b1, 1'b?} : ctrl_o.alu_op = ALU_XOR;
                    {OR, FUNCT7_ANY, 1'b1, 1'b?} : ctrl_o.alu_op = ALU_OR;
                    {AND, FUNCT7_ANY, 1'b1, 1'b?} : ctrl_o.alu_op = ALU_AND;
                    {SLL, FUNCT7_BASE, 1'b1, 1'b1} : ctrl_o.alu_op = ALU_SLL;
                    {SLL, FUNCT7_BASE[6:1], 1'b?, 1'b1, 1'b0} : ctrl_o.alu_op = ALU_SLL;

                    // R-type
                    {SLT, FUNCT7_BASE, 1'b0, 1'b?} : ctrl_o.alu_op = ALU_SLT;
                    {SLTU, FUNCT7_BASE, 1'b0, 1'b?} : ctrl_o.alu_op = ALU_SLTU;
                    {XOR, FUNCT7_BASE, 1'b0, 1'b?} : ctrl_o.alu_op = ALU_XOR;
                    {OR, FUNCT7_BASE, 1'b0, 1'b?} : ctrl_o.alu_op = ALU_OR;
                    {AND, FUNCT7_BASE, 1'b0, 1'b?} : ctrl_o.alu_op = ALU_AND;
                    {SLL, FUNCT7_BASE, 1'b0, 1'b?} : ctrl_o.alu_op = ALU_SLL;

                    // Right shift
                    {SR, FUNCT7_BASE, 1'b?, 1'b1} : ctrl_o.alu_op = ALU_SRL;
                    {SR, FUNCT7_BASE, 1'b0, 1'b0} : ctrl_o.alu_op = ALU_SRL;
                    {SR, FUNCT7_ALT, 1'b?, 1'b1} : ctrl_o.alu_op = ALU_SRA;
                    {SR, FUNCT7_ALT, 1'b0, 1'b0} : ctrl_o.alu_op = ALU_SRA;
                    // bit 0 of where funct7 normally is is the MSB of shamt
                    {SR, FUNCT7_BASE[6:1], 1'b?, 1'b1, 1'b0} : ctrl_o.alu_op = ALU_SRL;
                    {SR, FUNCT7_ALT[6:1], 1'b?, 1'b1, 1'b0} : ctrl_o.alu_op = ALU_SRA;
                    default : ctrl_o.illegal = '1;
                endcase

                ctrl_o.wb_sel = WB_ALU;
                ctrl_o.reg_write = '1;
            end
            MISC_MEM : begin
                ctrl_o.inst_fmt = IMM_I;
                // This covers FENCE, FENCE.TSO, and PAUSE
                // This instruction is illegal if funct3 != 000
                if (funct3 != 3'b000) ctrl_o.illegal = '1;
                // Otherwise, as this is a single cycle core, FENCE is essentially a NOP
            end
            SYSTEM : begin
                ctrl_o.inst_fmt = IMM_I;
                case (funct3)
                    // No support yet for ECALL/EBREAK, so they're treated as NOPs
                    // But some instructions of this form are instead illegal
                    PRIV : case (inst_i)
                        ECALL : ctrl_o.ecall = '1;
                        EBREAK : ctrl_o.ebreak = '1;
                        MRET : begin
                            // In the case of a return from a trap, we want to branch to the MEPC
                            ctrl_o.mret = '1;
                            ctrl_o.branch_src = SRC_MEPC;
                            ctrl_o.branch = '1;
                            if (current_privilege_i != M_MODE) begin
                                ctrl_o.illegal = '1;
                            end
                        end
                        SRET : begin
                            // In the case of a return from a trap, we want to branch to the SEPC
                            ctrl_o.sret = '1;
                            ctrl_o.branch_src = SRC_SEPC;
                            ctrl_o.branch = '1;
                            if (current_privilege_i != S_MODE) begin
                                ctrl_o.illegal = '1;
                            end
                        end
                        // WFI is implemented as a NOP, which is legal.
                        WFI : ;
                        default : ctrl_o.illegal = '1;
                    endcase

                    // Immediate and register operand CSR operations can use the same processing.
                    // For immediate instructions, though, rs1_addr is treated as a 5 bit unsigned
                    // immediate value.
                    CSRRW, CSRRWI : begin
                        ctrl_o.reg_write = '1;
                        ctrl_o.wb_sel = WB_CSR;

                        ctrl_o.csr_write = '1;
                        // If rd is x0, a read does not take place
                        if (ctrl_o.rd_addr != '0)
                            ctrl_o.csr_read = '1;

                        if (funct3 == CSRRWI) ctrl_o.csr_imm = '1;
                    end

                    CSRRS, CSRRSI : begin
                        ctrl_o.reg_write = '1;
                        ctrl_o.wb_sel = WB_CSR;

                        // If rs1/uimm is x0/0, a write doesn't take place
                        if (ctrl_o.rs1_addr != '0)
                            ctrl_o.csr_write = '1;

                        ctrl_o.csr_read = '1;
                        ctrl_o.csr_wb_sel = WB_SET_BITS;

                        if (funct3 == CSRRSI) ctrl_o.csr_imm = '1;
                    end

                    CSRRC, CSRRCI : begin
                        ctrl_o.reg_write = '1;
                        ctrl_o.wb_sel = WB_CSR;

                        // If rs1/uimm is x0/0, a write doesn't take place
                        if (ctrl_o.rs1_addr != '0)
                            ctrl_o.csr_write = '1;

                        ctrl_o.csr_read = '1;
                        ctrl_o.csr_wb_sel = WB_CLEAR_BITS;

                        if (funct3 == CSRRCI) ctrl_o.csr_imm = '1;
                    end

                    default: ctrl_o.illegal = '1;
                endcase
            end
            default : begin
                ctrl_o.illegal = '1;
            end
        endcase

        // If we have an illegal instruction, we want to also clear all side effects
        if (ctrl_o.illegal) begin
            ctrl_o = '0;
            ctrl_o.illegal = '1;
        end

        // Control invariants
        assert(!(ctrl_o.mem_read && ctrl_o.mem_write)) else $fatal(1, "Should not be reading and writing through the same memory channel at the same time!");
    end
endmodule : control_unit
