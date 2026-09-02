package riscv;

    localparam int WWIDTH     = 32;
    localparam int IALIGN     = 32;
    localparam int XLEN       = 32;
    localparam int REG_ADDR_W = 5;
    localparam int NUM_REGS   = 32;

    localparam logic [XLEN-1:0] PC_INC   = 32'd4;
    localparam logic [REG_ADDR_W-1:0] X0 = 5'd0;

    localparam logic [XLEN-1:0] RESET_PC           = 32'd0;
    localparam logic [XLEN-1:0] IMEM_START_ADDRESS = 'h00_00_00_00;
    localparam logic [XLEN-1:0] IMEM_END_ADDRESS   = 'h00_0f_ff_ff;
    localparam logic [XLEN-1:0] DMEM_START_ADDRESS = 'h00_10_00_00;
    localparam logic [XLEN-1:0] DMEM_END_ADDRESS   = 'h00_1f_ff_ff;

    // ======================
    // Instruction field bits
    // ======================
    localparam int OPCODE_LSB = 0,  OPCODE_MSB = 6;
    localparam int RD_LSB     = 7,  RD_MSB     = 11;
    localparam int FUNCT3_LSB = 12, FUNCT3_MSB = 14;
    localparam int RS1_LSB    = 15, RS1_MSB    = 19;
    localparam int RS2_LSB    = 20, RS2_MSB    = 24;
    localparam int FUNCT7_LSB = 25, FUNCT7_MSB = 31;
    localparam int IMM_SIGN = 31;

    // =======
    // Opcodes
    // =======
    localparam logic [6:0] LUI      = 7'b0110111;
    localparam logic [6:0] AUIPC    = 7'b0010111;
    localparam logic [6:0] JAL      = 7'b1101111;
    localparam logic [6:0] JALR     = 7'b1100111;
    localparam logic [6:0] BRANCH   = 7'b1100011;
    localparam logic [6:0] LOAD     = 7'b0000011;
    localparam logic [6:0] STORE    = 7'b0100011;
    localparam logic [6:0] OP_IMM   = 7'b0010011;
    localparam logic [6:0] OP       = 7'b0110011;
    localparam logic [6:0] MISC_MEM = 7'b0001111;
    localparam logic [6:0] SYSTEM   = 7'b1110011;

    // ======================
    // OP[-IMM] funct3 values
    // ======================
    localparam logic [2:0] ADD_SUB = 3'b000;
    localparam logic [2:0] SLT     = 3'b010;
    localparam logic [2:0] SLTU    = 3'b011;
    localparam logic [2:0] XOR     = 3'b100;
    localparam logic [2:0] OR      = 3'b110;
    localparam logic [2:0] AND     = 3'b111;
    localparam logic [2:0] SLL     = 3'b001;
    localparam logic [2:0] SR      = 3'b101;

    // ====================
    // BRANCH funct3 values
    // ====================
    localparam logic [2:0] EQ  = 3'b000;
    localparam logic [2:0] NE  = 3'b001;
    localparam logic [2:0] LT  = 3'b100;
    localparam logic [2:0] GE  = 3'b101;
    localparam logic [2:0] LTU = 3'b110;
    localparam logic [2:0] GEU = 3'b111;

    // ==================
    // LOAD funct3 values
    // ==================
    localparam logic [2:0] LB  = 3'b000;
    localparam logic [2:0] LH  = 3'b001;
    localparam logic [2:0] LW  = 3'b010;
    localparam logic [2:0] LBU = 3'b100;
    localparam logic [2:0] LHU = 3'b101;

    // ===================
    // STORE funct3 values
    // ===================
    localparam logic [2:0] SB = 3'b000;
    localparam logic [2:0] SH = 3'b001;
    localparam logic [2:0] SW = 3'b010;

    // =============
    // funct7 values
    // =============
    localparam logic [6:0] FUNCT7_BASE = 7'b0000000;
    localparam logic [6:0] FUNCT7_ALT  = 7'b0100000; // SUB/SRA/SRAI
    localparam logic [6:0] FUNCT7_ANY  = 7'b???????;

    // ===========
    // misc values
    // ===========
    localparam logic [2:0] JALR_F3     = 3'b000;
    localparam logic [2:0] FENCE_F3    = 3'b000;
    localparam logic [2:0] SYSTEM_F3   = 3'b000;
    localparam logic [11:0] ECALL_IMM  = 12'h000;
    localparam logic [11:0] EBREAK_IMM = 12'h001;

    // ===================
    // SYSTEM instructions
    // ===================
    localparam logic [31:0] ECALL  = 32'b000000000000_00000_000_00000_1110011;
    localparam logic [31:0] EBREAK = 32'b000000000001_00000_000_00000_1110011;


    // =============================
    // immediate instruction formats
    // =============================
    typedef enum logic [2:0] {
        IMM_R,      // No immediate
        IMM_I,      // 12 bit immediate
        IMM_S,      // 12 bit immediate, split across two fields
        IMM_B,      // 13 bit immediate, lowest bit set to 0
        IMM_U,      // 20-bit upper immediate
        IMM_J       // 20-bit signed jump offset
    } inst_fmt_t;

    // ==========================
    // instruction control packet
    // ==========================
    typedef enum logic [3:0] {
        ALU_ADD,
        ALU_SUB,
        ALU_SLT,
        ALU_SLTU,
        ALU_XOR,
        ALU_OR,
        ALU_AND,
        ALU_SLL,
        ALU_SRL,
        ALU_SRA
    } alu_op_t;

    // Value written back into register
    typedef enum logic [1:0] {
        WB_ALU,                 // ALU output
        WB_MEM,                 // Data from memory
        WB_PC_PLUS_4,           // Writeback address
        WB_IMM                  // Immediate value (LUI)
    } wb_sel_t;

    typedef enum logic [1:0] {
        MEM_NONE,
        MEM_BYTE,
        MEM_HALF,
        MEM_WORD
    } mem_size_t;

    typedef enum logic {
        MEM_UNSIGNED,
        MEM_SIGNED
    } mem_signed_t;

    typedef enum logic [2:0] {
        COND_EQ,
        COND_NE,
        COND_LT,
        COND_GE,
        COND_LTU,
        COND_GEU
    } branch_cond_t;

    // Used to select whether RS1 or the PC is used as operand 1 in the ALU.
    typedef enum logic {
        RS1,
        PC
    } op1_src_t;

    typedef struct packed {
        inst_fmt_t             inst_fmt;

        op1_src_t              op1_src;

        logic [REG_ADDR_W-1:0] rs1_addr;
        logic [REG_ADDR_W-1:0] rs2_addr;
        logic [REG_ADDR_W-1:0] rd_addr;

        alu_op_t               alu_op;
        logic                  alu_sel_imm;

        logic                  branch;
        branch_cond_t          branch_cond;
        logic                  jal;
        logic                  jalr;

        logic                  mem_read;
        logic                  mem_write;
        mem_size_t             mem_size;
        mem_signed_t           mem_signed;

        wb_sel_t               wb_sel;
        logic                  reg_write;
        logic                  illegal;
    } ctrl_t;
endpackage
