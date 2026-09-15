package riscv;

    localparam int WWIDTH     = 64;
    localparam int IALIGN     = 32;
    localparam int XLEN       = 64;
    localparam int PHYS_ADDR_WIDTH = 56;
    localparam int REG_ADDR_W = 5;
    localparam int NUM_REGS   = 32;

    localparam logic [XLEN-1:0] PC_INC   = 32'd4;
    localparam logic [REG_ADDR_W-1:0] X0 = 5'd0;

    localparam logic [XLEN-1:0] RESET_PC           = 32'd0;
    localparam logic [PHYS_ADDR_WIDTH-1:0] MEM_START_ADDRESS = 'h00_00_00_00;
    localparam logic [PHYS_ADDR_WIDTH-1:0] MEM_END_ADDRESS   = 'h00_1f_ff_ff;
    localparam logic [PHYS_ADDR_WIDTH-1:0] MTIME_ADDR   = 'h10_00_00_00_00_00_00;
    localparam logic [PHYS_ADDR_WIDTH-1:0] MTIMECMP_ADDR   = 'h10_00_00_00_00_00_08;

    localparam int MEM_READ_PORTS = 2;
    localparam int TLB_SIZE = 16;
    localparam int PTE_LEVELS = 3;
    localparam logic [XLEN-1:0] PTESIZE = 8;
    localparam logic [XLEN-1:0] PAGESIZE = 1 << 12;  // 4 KiB pages

    localparam logic [IALIGN-1:0] RISCV_NOP = 'h00000013;

    // satp fields
    localparam int SATP_MODE_MSB = 63;
    localparam int SATP_MODE_LSB = 60;
    localparam int SATP_ASID_MSB = 59;
    localparam int SATP_ASID_LSB = 44;
    localparam int SATP_PPN_MSB = 43;
    localparam int SATP_PPN_LSB = 0;

    typedef enum logic [3:0] {
        MODE_BARE = '0,
        MODE_SV39 = 'd8
    } satp_mode_t;

    // pte (page table entry) fields
    localparam int PTE_D = 7;
    localparam int PTE_A = 6;
    localparam int PTE_G = 5;
    localparam int PTE_U = 4;
    localparam int PTE_X = 3;
    localparam int PTE_W = 2;
    localparam int PTE_R = 1;
    localparam int PTE_V = 0;
    localparam int PTE_RESERVED_MSB = 63;
    localparam int PTE_RESERVED_LSB = 54;

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

    // ============
    // Memory stuff
    // ============
    typedef struct packed {
        // a VPN is 27 bits - 3x9
        logic [26:0] vpn;
        logic [15:0] asid;
        logic [2:0] leaf_level;

        logic [43:0] ppn;
        logic accessed;
        logic dirty;
        logic global_mapping;
        logic user;
        logic execute;
        logic write;
        logic read;
        logic valid;
    } tlb_entry_t;

    // SFENCE.VMA's operands can be reduced in EX, after normal operand
    // forwarding.  This is the complete selector needed at retirement; it
    // deliberately retains the x0 selectors because x0 means "all", whereas
    // a non-x0 register whose value is zero selects VPN/ASID zero.
    typedef struct packed {
        logic        valid;
        logic        vaddr_all;
        logic        vaddr_canonical;
        logic [26:0] vpn;
        logic        asid_all;
        logic [SATP_ASID_MSB-SATP_ASID_LSB:0] asid;
    } sfence_sel_t;

    typedef enum logic [1:0] {
        MREAD,  // read
        MWRITE, // write
        MFETCH // instruction fetch
    } mem_op_t;

    typedef enum logic [2:0] {
        MEM_NONE,
        MEM_BYTE,
        MEM_HALF,
        MEM_WORD,
        MEM_DOUBLE
    } mem_size_t;

    typedef enum logic {
        MEM_UNSIGNED,
        MEM_SIGNED
    } mem_signed_t;

    typedef enum logic [2:0] {
        FAULT_NONE,
        PMA_FETCH,
        PMA_WRITE,
        PMA_READ,
        PMP_FETCH,
        PMP_WRITE,
        PMP_READ
    } mem_fault_t;

    typedef struct packed {
        logic valid;
        logic mem_access_requested;
        logic [XLEN-1:0] address;
        logic [XLEN-1:0] virtual_address;
        mem_size_t size;
        mem_signed_t mem_signed;
        // op and op_original are very similar. The distinction is that op is the actual operation,
        // relevant to the permissions of the PMA/PMP, while op_original is the original operation
        // that resulted in this. This is relevant for page table walks, where they are treated as
        // reads, but if they result in PMA/PMP issues, they raise an access-fault of the original
        // access type.
        // while
        mem_op_t op;
        mem_op_t op_original;
        machine_privilege_t effective_privilege;
    } mem_req_t;

    typedef struct packed {
        // valid is only used for reads/fetches. For writes, it is a static 0
        // Currently, since writes are single cycle and guaranteed to complete in that cycle, it is
        // not necessary to have the valid signal.
        logic valid;
        logic [XLEN-1:0] data;
    } mem_res_t;

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
    localparam int PMA_ENTRY_COUNT = 4;
    localparam int PMP_ADDR_WIDTH = PHYS_ADDR_WIDTH - 2;

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
    localparam int MSTATUS_SIE = 1;
    localparam int MSTATUS_MIE = 3;
    localparam int MSTATUS_SPIE = 5;
    localparam int MSTATUS_MPIE = 7;
    localparam int MSTATUS_SPP = 8;
    localparam int MSTATUS_MPRV = 17;
    localparam int MSTATUS_SUM = 18;
    localparam int MSTATUS_MXR = 19;
    localparam int MSTATUS_TVM = 20;
    localparam int MSTATUS_TW = 21;
    localparam int MSTATUS_TSR = 22;
    localparam int MSTATUS_UXL_MSB = 33;
    localparam int MSTATUS_UXL_LSB = 32;
    localparam int MSTATUS_SXL_MSB = 35;
    localparam int MSTATUS_SXL_LSB = 34;

    // ========
    // counters
    // ========
    localparam int COUNT_CY = 0;
    localparam int COUNT_TM = 1;
    localparam int COUNT_IR = 2;

    // ======================
    // CSR register addresses
    // ======================
    localparam logic [1:0] CSR_READ_ONLY = 2'b11;

    // # Supervisor-level CSRs
    // ### Supervisor trap setup
    localparam logic [11:0] SSTATUS      = 'h100;
    localparam logic [11:0] SIE          = 'h104;
    localparam logic [11:0] STVEC        = 'h105;
    localparam logic [11:0] SCOUNTEREN   = 'h106;

    // ### Supervisor configuration
    localparam logic [11:0] SENVCFG      = 'h10A;

    // ### Supervisor trap handling
    localparam logic [11:0] SSCRATCH     = 'h140;
    localparam logic [11:0] SEPC         = 'h141;
    localparam logic [11:0] SCAUSE       = 'h142;
    localparam logic [11:0] STVAL        = 'h143;
    localparam logic [11:0] SIP          = 'h144;

    // ### Supervisor protection and translation
    localparam logic [11:0] SATP         = 'h180;

    // ### Supervisor timer compare --- Sstc
    localparam logic [11:0] STIMECMP     = 'h14D;

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
    localparam logic [11:0] MEDELEG        = 'h302;
    localparam logic [11:0] MIDELEG        = 'h303;
    localparam logic [11:0] MIE            = 'h304;
    localparam logic [11:0] MTVEC          = 'h305;
    localparam logic [11:0] MCOUNTEREN     = 'h306;

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
    localparam int MENVCFG_STCE            = 63;
    localparam logic [XLEN-1:0] MENVCFG_WRITABLE_MASK = 64'h8000_0000_0000_0001;
    localparam logic [11:0] MSECCFG        = 'h747;

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

    // ### User counter/timers
    // Read-only views of the machine cycle and instruction-retired counters.
    localparam logic [11:0] CYCLE          = 'hC00;
    localparam logic [11:0] TIME           = 'hC01;
    localparam logic [11:0] INSTRET        = 'hC02;
    localparam logic [11:0] HPMCOUNTER3    = 'hC04;
    localparam logic [11:0] HPMCOUNTER31   = 'hC1F;

    // Includes timers and other things which can change between CSR read in ID and writeback in WB
    // without an explicit CSR modification. The only registers which currently aren't covered which
    // have this issue are MIP and SIP, which can sometimes change their value but not flush if
    // interrupts are not enabled. However, in this case, there is no time that is architecturally
    // "correct", per se, to have the MIP and SIP bits set.
    function automatic logic is_late_csr(input logic [11:0] csr_addr);
        return csr_addr == MCYCLE || csr_addr == CYCLE || csr_addr == TIME
            || csr_addr == MINSTRET || csr_addr == INSTRET;
    endfunction

    // ### Machine counter setup
    localparam logic [11:0] MCOUNTINHIBIT  = 'h320;
    localparam logic [11:0] MCYCLECFG      = 'h321;
    localparam logic [11:0] MINSTRETCFG    = 'h322;
    localparam logic [11:0] MHPMEVENT3     = 'h323;
    localparam logic [11:0] MHPMEVENT31    = 'h33F;

    // ==================
    // CSR default values
    // ==================
    // For any CSR that has a non-zero default value, its default value is (and is explained) here.
    // MISA: 63:62 => XLEN = 64
    //       61:26 => static value (all 0s)
    //       25:0  => extensions (I, S, and U are implemented)
    localparam int MISA_EXT_I = 8;
    localparam int MISA_EXT_S = 18;
    localparam int MISA_EXT_U = 20;
    localparam logic [XLEN-1:0] MISA_VAL     = (XLEN'(2) << (XLEN - 2))
                                               | (XLEN'(1) << MISA_EXT_I)
                                               | (XLEN'(1) << MISA_EXT_S)
                                               | (XLEN'(1) << MISA_EXT_U);

    // mstatus: all 0s, but MPP is reset to equal M (11) so an MRET before the first TRAP
    // doesn't drop the mode to user.
    // RV64 requires both supported XLEN fields to read as 2 (64-bit).
    localparam logic [XLEN-1:0] MSTATUS_VAL  = 64'h0000_000a_0000_1800;
    localparam logic [XLEN-1:0] MSTATUSH_VAL = 'h0;
    // Writable mstatus bits modeled by this core.  MPP supports M, S, and U;
    // the reserved encoding is legalized to M.
    // TODO: Add TVM (20), TW (21), and TSR (22) when enforcing M-mode
    // restrictions on S-mode. TVM restricts satp/SFENCE.VMA, TW restricts
    // WFI below M-mode, and TSR restricts SRET in S-mode.
    localparam logic [XLEN-1:0] MSTATUS_WRITE_MASK_VAL = (XLEN'(1) << MSTATUS_MPP_MSB)
                                                        | (XLEN'(1) << MSTATUS_MPP_LSB)
                                                        | (XLEN'(1) << MSTATUS_MPRV)
                                                        | (XLEN'(1) << MSTATUS_MPIE)
                                                        | (XLEN'(1) << MSTATUS_SPP)
                                                        | (XLEN'(1) << MSTATUS_SPIE)
                                                        | (XLEN'(1) << MSTATUS_MIE)
                                                        | (XLEN'(1) << MSTATUS_SIE)
                                                        | (XLEN'(1) << MSTATUS_SUM)
                                                        | (XLEN'(1) << MSTATUS_MXR)
                                                        | (XLEN'(1) << MSTATUS_TVM)
                                                        | (XLEN'(1) << MSTATUS_TW)
                                                        | (XLEN'(1) << MSTATUS_TSR);

    // mtvec will, by default, have the base address as RESET_PC
    localparam logic [XLEN-1:0] MVEC_VAL = {RESET_PC[XLEN-1:2], TRAP_DIRECT};

    // Bits of mstatus exposed by the currently modeled portion of sstatus.
    localparam logic [XLEN-1:0] SSTATUS_MASK = (XLEN'(1) << MSTATUS_SIE)
                                               | (XLEN'(1) << MSTATUS_SPIE)
                                               | (XLEN'(1) << MSTATUS_SPP)
                                               | (XLEN'(1) << MSTATUS_SUM)
                                               | (XLEN'(1) << MSTATUS_MXR)
                                               | (XLEN'(3) << MSTATUS_UXL_LSB);
    // UXL is visible through sstatus in RV64 but is read-only.
    localparam logic [XLEN-1:0] SSTATUS_WRITE_MASK = SSTATUS_MASK
                                                     & ~(XLEN'(3) << MSTATUS_UXL_LSB);


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
    localparam logic [6:0] LUI         = 7'b0110111;
    localparam logic [6:0] AUIPC       = 7'b0010111;
    localparam logic [6:0] JAL         = 7'b1101111;
    localparam logic [6:0] JALR        = 7'b1100111;
    localparam logic [6:0] BRANCH      = 7'b1100011;
    localparam logic [6:0] LOAD        = 7'b0000011;
    localparam logic [6:0] STORE       = 7'b0100011;
    localparam logic [6:0] OP_IMM_WORD = 7'b0011011;
    localparam logic [6:0] OP_WORD     = 7'b0111011;
    localparam logic [6:0] OP_IMM      = 7'b0010011;
    localparam logic [6:0] OP          = 7'b0110011;
    localparam logic [6:0] MISC_MEM    = 7'b0001111;
    localparam logic [6:0] SYSTEM      = 7'b1110011;

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
    localparam logic [2:0] LD  = 3'b011;
    localparam logic [2:0] LBU = 3'b100;
    localparam logic [2:0] LHU = 3'b101;
    localparam logic [2:0] LWU = 3'b110;

    // ===================
    // STORE funct3 values
    // ===================
    localparam logic [2:0] SB = 3'b000;
    localparam logic [2:0] SH = 3'b001;
    localparam logic [2:0] SW = 3'b010;
    localparam logic [2:0] SD = 3'b011;

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
    localparam logic [31:0] SRET   = 32'h1020_0073;
    localparam logic [31:0] WFI    = 32'h1050_0073;
    localparam logic [31:0] SF_VMA = 32'b0001001_?????_?????_000_00000_1110011;
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

    typedef enum logic [1:0] {
        SRC_ALU,
        SRC_MEPC,
        SRC_SEPC
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
        logic                  alu_word_op;

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

        logic                  tlb_invalidate;
        logic                  wfi;

        logic                  ebreak;
        logic                  ecall;
        logic                  mret;
        logic                  sret;

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

    // Interrupt and delegation masks are defined from their architectural
    // cause numbers so they remain correct if XLEN or the implemented set
    // changes.  This core exposes all six standard interrupt-enable and
    // delegation bits, and the standard exceptions that can originate below
    // M-mode.
    localparam logic [XLEN-1:0] STANDARD_INTERRUPT_MASK = (XLEN'(1) << S_SOFTWARE)
                                                         | (XLEN'(1) << M_SOFTWARE)
                                                         | (XLEN'(1) << S_TIMER)
                                                         | (XLEN'(1) << M_TIMER)
                                                         | (XLEN'(1) << S_EXTERNAL)
                                                         | (XLEN'(1) << M_EXTERNAL);
    // Machine interrupts are NOT delegatable
    localparam logic [XLEN-1:0] SUPERVISOR_INTERRUPT_MASK = (XLEN'(1) << S_SOFTWARE)
                                                         | (XLEN'(1) << S_TIMER)
                                                         | (XLEN'(1) << S_EXTERNAL);
    localparam logic [XLEN-1:0] MIP_WRITABLE_MASK = (XLEN'(1) << S_SOFTWARE)
                                                    | (XLEN'(1) << S_EXTERNAL);
    localparam logic [XLEN-1:0] MEDELEG_WRITABLE_MASK = (XLEN'(1) << INST_ACCESS_FAULT)
                                                        | (XLEN'(1) << ILLEGAL_INSTRUCTION)
                                                        | (XLEN'(1) << BREAKPOINT)
                                                        | (XLEN'(1) << LOAD_ADDRESS_MISALIGNED)
                                                        | (XLEN'(1) << LOAD_ACCESS_FAULT)
                                                        | (XLEN'(1) << STORE_ADDRESS_MISALIGNED)
                                                        | (XLEN'(1) << STORE_ACCESS_FAULT)
                                                        | (XLEN'(1) << ECALL_FROM_U_MODE)
                                                        | (XLEN'(1) << INSTRUCTION_PAGE_FAULT)
                                                        | (XLEN'(1) << LOAD_PAGE_FAULT)
                                                        | (XLEN'(1) << STORE_PAGE_FAULT);

    typedef struct packed {
        logic                  is_trap;
        logic                  is_interrupt;
        trap_interrupt_cause_t interrupt_cause;
        trap_exception_cause_t exception_cause;
        machine_privilege_t    dest_machine_privilege;
        logic [XLEN-1:0]       pc;
        logic [XLEN-1:0]       tval;
    } trap_t;

    typedef enum logic {
        UNALIGNED,
        DOUBLE_ALIGNED
    } alignment_t;

    // ===========================
    // Physical memory attribution
    // ===========================
    typedef struct packed {
        logic [PHYS_ADDR_WIDTH-1:0] addr_low;
        logic [PHYS_ADDR_WIDTH-1:0] addr_high;
        logic        main;          // High if part of main memory, low if MMIO (ie should not be executable)
        logic        writable;
        logic        readable;
        alignment_t  alignment;
        // logic        bufferable; // relevant for future
        // logic        cacheable;
        // logic        atomic;
    } pma_cfg_t;

    function automatic [26:0] vpn_mask(
        input logic [2:0] leaf_level,
        input [26:0] vpn
    );
        if (leaf_level == 0) begin
            return vpn;
        end else if (leaf_level == 1) begin
            return {vpn[26:9], 9'b0};
        end else if (leaf_level == 2) begin
            return {vpn[26:18], 18'b0};
        end
        // fallback
        return vpn;
    endfunction

    function automatic [8:0] vpn_index(
        input logic [2:0] level,
        input [26:0] vpn
    );
        if (level == 0) begin
            return vpn[8:0];
        end else if (level == 1) begin
            return vpn[17:9];
        end else if (level == 2) begin
            return vpn[26:18];
        end
        // fallback
        return vpn[8:0];
    endfunction

    function automatic [43:0] ppn_index(
        input logic [2:0] level,
        input [43:0] ppn
    );
        if (level == 0) begin
            return 44'(ppn[8:0]);
        end else if (level == 1) begin
            return 44'(ppn[17:9]);
        end else if (level == 2) begin
            return 44'(ppn[43:18]);
        end
        // fallback
        return 44'(ppn[8:0]);
    endfunction

    function automatic logic [XLEN-1:0] ppn_to_addr(
        input logic [2:0] leaf_level,
        input logic [XLEN-1:0] vaddr,
        input logic [43:0] ppn
    );
        if (leaf_level == 0) begin
            // 56 bit physical address, zero extended to XLEN (64)
            return {8'b0, ppn, vaddr[11:0]};
        end else if (leaf_level == 1) begin
            // This is a megapage - the first VPN field is part of the offset
            return {8'b0, ppn[43:9], vaddr[20:0]};
        end else if (leaf_level == 2) begin
            // This is a gigapage - the first two VPN fields are part of the offset
            return {8'b0, ppn[43:18], vaddr[29:0]};
        end
        // fallback, should not be accessed
        return {8'b0, ppn, vaddr[11:0]};
    endfunction
endpackage
