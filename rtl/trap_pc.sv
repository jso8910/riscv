import riscv::*;

module trap_pc (
    input logic             commit_i,
    input trap_t            trap_i,
    input logic [XLEN-1:0]  mtvec_i,
    input logic [XLEN-1:0]  stvec_i,
    output logic [XLEN-1:0] next_pc_o,
    output logic            trap_redirect_o
);
    logic [XLEN-1:0] trap_vec;

    always_comb begin
        next_pc_o = '0;
        trap_redirect_o = '0;
        case (trap_i.dest_machine_privilege)
            M_MODE : trap_vec = mtvec_i;
            S_MODE : trap_vec = stvec_i;
            default : trap_vec = mtvec_i;
        endcase
        // We don't want to flush the pipeline if the data in the MEM/WB register isn't valid
        // (condition for commit_i)
        if (commit_i) begin
            // Set next PC.
            if (trap_i.is_trap) begin
                trap_redirect_o = '1;
                case (trap_mode_t'(trap_vec[1:0]))
                    TRAP_DIRECT : next_pc_o = {trap_vec[XLEN-1:2], 2'b00};
                    TRAP_VEC : begin
                        // If an asynchronous interrupt, set PC to BASE + 4*cause
                        if (trap_i.is_interrupt) begin
                            next_pc_o = {trap_vec[XLEN-1:2], 2'b00} + 4*(XLEN'(trap_i.interrupt_cause));
                        end else
                            next_pc_o = {trap_vec[XLEN-1:2], 2'b00};
                    end
                    // xTVEC writes are legalized to direct or vectored mode. Using
                    // direct mode while reset-state signals settle to avoid issues.
                    default: next_pc_o = {trap_vec[XLEN-1:2], 2'b00};
                endcase
            end
        end
    end
endmodule : trap_pc
