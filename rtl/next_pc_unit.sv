import riscv::*;

module next_pc_unit (
    input ctrl_t            ctrl_i,
    input logic [XLEN-1:0]  pc_i,
    input logic [XLEN-1:0]  pred_pc_i,
    input logic [XLEN-1:0]  rs1_data_i,
    input logic [XLEN-1:0]  rs2_data_i,
    input logic [XLEN-1:0]  alu_res_i,
    input logic [XLEN-1:0]  mepc_i,
    // input logic [XLEN-1:0]  mtvec_i,
    input logic [XLEN-1:0]  sepc_i,
    // input logic [XLEN-1:0]  stvec_i,
    // input trap_t            trap_i,
    output logic [XLEN-1:0] next_pc_o,
    output logic            redirect_o,
    output logic            address_misaligned_o
);
    logic [XLEN-1:0] op1, op2;
    logic signed [XLEN-1:0] op1_signed, op2_signed;
    logic [XLEN-1:0] pc_seq, pc_branch, trap_vec;
    logic branch_taken;

    assign op1 = rs1_data_i, op2 = rs2_data_i;
    assign op1_signed = signed'(op1), op2_signed = signed'(op2);
    assign pc_seq = pc_i + PC_INC;

    assign redirect_o = pred_pc_i != next_pc_o;

    always_comb begin
        // In the case of a return from a trap, we want to branch to the MEPC
        case (ctrl_i.branch_src)
            SRC_ALU : pc_branch = alu_res_i;
            SRC_MEPC : pc_branch = mepc_i;
            SRC_SEPC : pc_branch = sepc_i;
            default : begin
                pc_branch = alu_res_i;
                $fatal(1);
            end
        endcase
        branch_taken = 1'b0;
        address_misaligned_o = '0;

        // Bit 0 must be cleared for JALR
        if (ctrl_i.jalr) pc_branch = pc_branch & ~(XLEN'(1'b1));

        if (ctrl_i.jal || ctrl_i.jalr || ctrl_i.mret || ctrl_i.sret) branch_taken = 1'b1;
        else if (ctrl_i.branch) begin
            case (ctrl_i.branch_cond)
                COND_EQ : branch_taken = op1 == op2;
                COND_NE : branch_taken = op1 != op2;
                COND_LT : branch_taken = op1_signed < op2_signed;
                COND_GE : branch_taken = op1_signed >= op2_signed;
                COND_LTU : branch_taken = op1 < op2;
                COND_GEU : branch_taken = op1 >= op2;
                default : branch_taken = '1;
            endcase
        end

        // If branch is not aligned.
        // NOTE: must change if IALIGN changes.
        if (branch_taken && (pc_branch[1:0] != 2'b00))
            address_misaligned_o = '1;
    end

    always_comb begin
        // case (trap_i.dest_machine_privilege)
        //     M_MODE : trap_vec = mtvec_i;
        //     S_MODE : trap_vec = stvec_i;
        //     default : trap_vec = mtvec_i;
        // endcase
        // // Set next PC.  This is separate from branch-target alignment so an
        // // instruction-address-misaligned exception cannot form a combinational
        // // loop through trap generation.
        // if (trap_i.is_trap) begin
        //     case (trap_mode_t'(trap_vec[1:0]))
        //         TRAP_DIRECT : next_pc_o = {trap_vec[XLEN-1:2], 2'b00};
        //         TRAP_VEC : begin
        //             // If an asynchronous interrupt, set PC to BASE + 4*cause
        //             if (trap_i.is_interrupt) begin
        //                 next_pc_o = {trap_vec[XLEN-1:2], 2'b00} + 4*(XLEN'(trap_i.interrupt_cause));
        //             end else
        //                 next_pc_o = {trap_vec[XLEN-1:2], 2'b00};
        //         end
        //         // xTVEC writes are legalized to direct or vectored mode. Use
        //         // direct mode defensively while reset-state signals settle.
        //         default: next_pc_o = {trap_vec[XLEN-1:2], 2'b00};
        //     endcase
        // end else if (branch_taken)
        if (branch_taken)
            next_pc_o = pc_branch;
        else
            next_pc_o = pc_seq;

    end
endmodule
