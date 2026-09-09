package riscv;

    localparam int WWIDTH     = 32;
    localparam int IALIGN     = 32;
    localparam int XLEN       = 32;
    localparam int REG_ADDR_W = 5;
    localparam int NUM_REGS   = 32;

    localparam logic [XLEN-1:0] PC_INC   = 32'd4;
    localparam logic [REG_ADDR_W-1:0] X0 = 5'd0;

    localparam logic [XLEN-1:0] RESET_PC           = 32'd0;
    localparam logic [XLEN-1:0] MEM_START_ADDRESS = 'h00_00_00_00;
    localparam logic [XLEN-1:0] MEM_END_ADDRESS   = 'h00_1f_ff_ff;

    typedef logic [XLEN-1:0] uintxlen_t;

    // ================
    // Privilege levels
    // ================
    typedef enum logic [1:0] {
        U_MODE = 2'b00,     // user
        S_MODE = 2'b01,     // supervisor
        RESERVED = 2'b10,   // reserved for hypervisor mode
        M_MODE = 2'b11      // machine
    } machine_privilege_t;

    localparam machine_privilege_t IMPLEMENTED_PRIVILEGE = M_MODE;

    // ================
    // Trap vector mode
    // ================
    typedef enum logic [1:0] {
        TRAP_DIRECT = 2'b00,
        TRAP_VEC = 2'b01
    } trap_mode_t;

    // ==========================
    // Physical memory protection
    // ==========================
    localparam int PMP_ENTRY_COUNT = 64;

    localparam int PMPCFG_L_IDX = 7;
    localparam int PMPCFG_A_MSB = 4;
    localparam int PMPCFG_A_LSB = 3;
    localparam int PMPCFG_X_IDX = 2;
    localparam int PMPCFG_W_IDX = 1;
    localparam int PMPCFG_R_IDX = 0;

    typedef struct packed {
        logic [7:0]      cfg;
        logic [XLEN-1:0] addr;
    } pmp_entry_t;

    typedef enum logic [1:0] {
        PMP_OFF   = 2'b00,
        PMP_TOR   = 2'b01,
        PMP_NA4   = 2'b10,
        PMP_NAPOT = 2'b11
    } pmp_addr_matching_t;

    // ==============
    // mstatus fields
    // ==============
    localparam int MSTATUS_MPP_MSB = 12;
    localparam int MSTATUS_MPP_LSB = 11;
    localparam int MSTATUS_MIE = 3;
    localparam int MSTATUS_MPIE = 7;
    localparam int MSTATUS_MPRV = 17;

    // ========
    // counters
    // ========
    localparam int MCOUNTINHIBIT_CY = 0;
    localparam int MCOUNTINHIBIT_IR = 2;

    // ======================
    // CSR register addresses
    // ======================
    localparam logic [1:0] CSR_READ_ONLY = 2'b11;

    // # Machine-level CSRs
    // ## Machine read only
    // ### Machine information registers
    localparam logic [11:0] MVENDORID    = 'hf11;
    localparam logic [11:0] MARCHID      = 'hf12;
    localparam logic [11:0] MIMPID       = 'hf13;
    localparam logic [11:0] MHARTID      = 'hf14;
    localparam logic [11:0] MCONFIGPTR   = 'hf15;

    // ## Machine read-write
    // ### Machine trap setup
    localparam logic [11:0] MSTATUS        = 'h300;
    localparam logic [11:0] MISA           = 'h301;
    // TODO: implement once S-mode is added
    // localparam logic [11:0] MEDELEG        = 'h302;
    // localparam logic [11:0] MIDELEG        = 'h303;
    localparam logic [11:0] MIE            = 'h304;
    localparam logic [11:0] MTVEC          = 'h305;
    // localparam logic [11:0] MCOUNTEREN     = 'h306;  TODO
    localparam logic [11:0] MSTATUSH       = 'h310;
    // localparam logic [11:0] MEDELEGH       = 'h312;  TODO

    // ### Machine trap handling
    localparam logic [11:0] MSCRATCH       = 'h340;
    localparam logic [11:0] MEPC           = 'h341;
    localparam logic [11:0] MCAUSE         = 'h342;
    localparam logic [11:0] MTVAL          = 'h343;
    localparam logic [11:0] MIP            = 'h344;
    // these are part of hypervisor/virtualization extensions, not needed
    // localparam logic [11:0] MTINST         = 'h34A;
    // localparam logic [11:0] MTVAL2         = 'h34B;

    // ### Machine configuration
    localparam logic [11:0] MENVCFG        = 'h30A;
    localparam logic [11:0] MENVCFGH       = 'h31A;
    localparam logic [11:0] MSECCFG        = 'h747;
    localparam logic [11:0] MSECCFGH       = 'h757;

    // ### Physical memory protection - defined with just first and last registers of each space
    localparam logic [11:0] PMPCFG0        = 'h3A0;
    localparam logic [11:0] PMPCFG15       = 'h3AF;
    localparam logic [11:0] PMPADDR0       = 'h3B0;
    localparam logic [11:0] PMPADDR63      = 'h3EF;

    // ### Machine counter/timers
    localparam logic [11:0] MCYCLE         = 'hB00;
    localparam logic [11:0] MINSTRET       = 'hB02;
    // In this implementation, mhpmcounter3-31 are going to be read-only 0, as well as mhpmevent3-31
    localparam logic [11:0] MHPMCOUNTER3   = 'hB03;
    localparam logic [11:0] MHPMCOUNTER31  = 'hB1F;
    localparam logic [11:0] MCYCLEH        = 'hB80;
    localparam logic [11:0] MINSTRETH      = 'hB82;
    // Same with the upper halves
    localparam logic [11:0] MHPMCOUNTER3H  = 'hB83;
    localparam logic [11:0] MHPMCOUNTER31H = 'hB9F;

    // ### User counter/timers
    // Read-only views of the machine cycle and instruction-retired counters.
    localparam logic [11:0] CYCLE          = 'hC00;
    localparam logic [11:0] INSTRET        = 'hC02;
    localparam logic [11:0] CYCLEH         = 'hC80;
    localparam logic [11:0] INSTRETH       = 'hC82;

    // ### Machine counter setup
    localparam logic [11:0] MCOUNTINHIBIT  = 'h320;
    localparam logic [11:0] MCYCLECFG      = 'h321;
    localparam logic [11:0] MINSTRETCFG    = 'h322;
    localparam logic [11:0] MHPMEVENT3     = 'h323;
    localparam logic [11:0] MHPMEVENT31    = 'h33F;
    localparam logic [11:0] MCYCLECFGH     = 'h721;
    localparam logic [11:0] MINSTRETCFGH   = 'h722;
    localparam logic [11:0] MHPMEVENT3H    = 'h723;
    localparam logic [11:0] MHPMEVENT31H   = 'h73F;

    // ==================
    // CSR default values
    // ==================
    // For any CSR that has a non-zero default value, its default value is (and is explained) here.
    // MISA: 31:30 => XLEN = 32
    //       29:26 => static value (all 0s)
    //       25:0  => extensions (bit 8 is set, RV32 base ISA)
    localparam logic [XLEN-1:0] MISA_VAL     = 'b01_0000_00000000000000000100000000;

    // mstatus/mstatush: all 0s, but MPP is reset to equal M (11) so an MRET before the first TRAP
    // doesn't drop the mode to user.
    localparam logic [XLEN-1:0] MSTATUS_VAL  = 'h0000_1800;
    localparam logic [XLEN-1:0] MSTATUSH_VAL = 'h0;
    // The only bits of mstatus which can be changed in this current machine mode
    // implementation are
    //  - 17    - MPRV // not yet
    //  - 12:11 - MPP, must be set to a legal privilege mode. Technically for now only M,
    //    but will implement all of M, S, and U
    //  - 7     - MPIE
    //  - 5     - SPIE // not yet
    //  - 3     - MIE
    //  - 1     - SIE // not yet
    // All other bits are kept the same (generally 0)
    localparam logic [XLEN-1:0] MSTATUS_WRITE_MASK_VAL = (1 <<MSTATUS_MPP_MSB) | (1 << MSTATUS_MPP_LSB) | (1 << MSTATUS_MPIE) | (1 << MSTATUS_MIE);
    // No bits in mstatush can be written in this implementation
    localparam logic [XLEN-1:0] MSTATUSH_WRITE_MASK_VAL = 'h00_00_00_00;

    // mtvec will, by default, have the base address as RESET_PC
    localparam logic [XLEN-1:0] MVEC_VAL = {RESET_PC[XLEN-1:2], TRAP_DIRECT};


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
    localparam logic [2:0] PRIV    = 3'b000;
    localparam logic [31:0] ECALL  = 32'b000000000000_00000_000_00000_1110011;
    localparam logic [31:0] EBREAK = 32'b000000000001_00000_000_00000_1110011;
    localparam logic [31:0] MRET   = 32'h3020_0073;
    localparam logic [31:0] WFI    = 32'h1050_0073;
    // todo: not implemented yet
    // localparam logic [31:0] SRET   = 32'h;

    // ===============
    // Zicsr extension
    // ===============
    localparam logic [2:0] CSRRW  = 3'b001;
    localparam logic [2:0] CSRRS  = 3'b010;
    localparam logic [2:0] CSRRC  = 3'b011;
    localparam logic [2:0] CSRRWI = 3'b101;
    localparam logic [2:0] CSRRSI = 3'b110;
    localparam logic [2:0] CSRRCI = 3'b111;


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
    typedef enum logic [2:0] {
        WB_ALU,                 // ALU output
        WB_MEM,                 // Data from memory
        WB_PC_PLUS_4,           // Writeback address
        WB_IMM,                 // Immediate value (LUI)
        WB_CSR                  // CSR value
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

    typedef enum logic {
        SRC_ALU,
        SRC_MEPC
    } branch_src_t;

    typedef enum logic [1:0] {
        WB_NORMAL,              // RS1/uimm value
        WB_SET_BITS,            // Sets bits using bitwise OR with rs1
        WB_CLEAR_BITS           // Clears bits in the CSR which are high in rs1
    } csr_wb_sel_t;

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
        branch_src_t           branch_src;

        logic                  mem_read;
        logic                  mem_write;
        mem_size_t             mem_size;
        mem_signed_t           mem_signed;

        wb_sel_t               wb_sel;
        logic                  reg_write;

        logic                  csr_write;
        logic                  csr_read;
        logic [11:0]           csr_addr;
        csr_wb_sel_t           csr_wb_sel;
        logic                  csr_imm;

        logic                  ebreak;
        logic                  ecall;
        logic                  mret;

        logic                  illegal;
    } ctrl_t;

    // =============
    // Trap handling
    // =============
    typedef enum logic[XLEN-2:0] {
        S_SOFTWARE = 'd1,
        M_SOFTWARE = 'd3,
        S_TIMER = 'd5,
        M_TIMER = 'd7,
        S_EXTERNAL = 'd9,
        M_EXTERNAL = 'd11,
        COUNTER_OVERFLOW = 'd13
    } trap_interrupt_cause_t;

    typedef enum logic[XLEN-2:0] {
        INST_ADDR_MISALIGNED = 'd0,
        INST_ACCESS_FAULT = 'd1,
        ILLEGAL_INSTRUCTION = 'd2,
        BREAKPOINT = 'd3,
        LOAD_ADDRESS_MISALIGNED = 'd4,
        LOAD_ACCESS_FAULT = 'd5,
        STORE_ADDRESS_MISALIGNED = 'd6,
        STORE_ACCESS_FAULT = 'd7,
        ECALL_FROM_U_MODE = 'd8,
        ECALL_FROM_S_MODE = 'd9,
        ECALL_FROM_M_MODE = 'd11,
        INSTRUCTION_PAGE_FAULT = 'd12,
        LOAD_PAGE_FAULT = 'd13,
        STORE_PAGE_FAULT = 'd15,
        DOUBLE_TRAP = 'd16,
        SOFTWARE_CHECK = 'd18,
        HARDWARE_ERROR = 'd19
    } trap_exception_cause_t;

    typedef struct packed {
        logic                  is_trap;
        logic                  is_interrupt;
        trap_interrupt_cause_t interrupt_cause;
        trap_exception_cause_t exception_cause;
        logic [XLEN-1:0]       pc;
        logic [XLEN-1:0]       tval;
    } trap_t;

    // ===========================
    // Physical memory attribution
    // ===========================
    typedef struct packed {
        logic [31:0] addr_low;
        logic [31:0] addr_high;
        logic        main;          // High if part of main memory, low if MMIO (ie should not be executable)
        logic        writable;
        logic        readable;
        // logic        bufferable; // relevant for future
        // logic        cacheable;
        // logic        atomic;
    } pma_cfg_t;
endpackage
