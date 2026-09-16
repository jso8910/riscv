// Registered harness for timing the three combinational stages of imul.
//
// This is deliberately a synthesis-only top.  The registers model the
// boundaries used by riscv_core without bringing the rest of the core's
// control, bypass, or memory logic into the timing result.
module imul_timing_wrapper (
    input  logic             clk,
    input  riscv::ctrl_t     ctrl_i,
    input  logic [riscv::XLEN-1:0] op1_data_i,
    input  logic [riscv::XLEN-1:0] op2_data_i,
    output logic [riscv::XLEN-1:0] imul_res_o
);
    import riscv::*;
    import imul_pkg::*;

    // Stage-0 flops make cycle 1 a register-to-register path.  The control
    // pipeline is included because its muxing is part of cycles 1 and 3.
    ctrl_t stage0_ctrl_q, stage1_ctrl_q, stage2_ctrl_q;
    logic [XLEN-1:0] stage0_op1_q, stage0_op2_q;
    logic [MAX_HEIGHT[0]-1:0] stage1_q [PP_WIDTH-1:0];
    logic [MAX_HEIGHT[6]-1:0] stage2_q [PP_WIDTH-1:0];
    logic [XLEN-1:0] stage3_q;

    logic [MAX_HEIGHT[0]-1:0] stage1_d [PP_WIDTH-1:0];
    logic [MAX_HEIGHT[6]-1:0] stage2_d [PP_WIDTH-1:0];
    logic [XLEN-1:0] stage3_d;

    imul_cycle1 u_imul_cycle1 (
        .ctrl_i        (stage0_ctrl_q),
        .op1_data_i    (stage0_op1_q),
        .op2_data_i    (stage0_op2_q),
        .imul_cycle1_o (stage1_d)
    );

    imul_cycle2 u_imul_cycle2 (
        .imul_cycle1_i (stage1_q),
        .imul_cycle2_o (stage2_d)
    );

    imul_cycle3 u_imul_cycle3 (
        .ctrl_i        (stage2_ctrl_q),
        .imul_cycle2_i (stage2_q),
        .imul_res_o    (stage3_d)
    );

    always_ff @(posedge clk) begin
        stage0_ctrl_q <= ctrl_i;
        stage0_op1_q  <= op1_data_i;
        stage0_op2_q  <= op2_data_i;
        stage1_ctrl_q <= stage0_ctrl_q;
        stage2_ctrl_q <= stage1_ctrl_q;
        stage1_q      <= stage1_d;
        stage2_q      <= stage2_d;
        stage3_q      <= stage3_d;
    end

    assign imul_res_o = stage3_q;
endmodule : imul_timing_wrapper
