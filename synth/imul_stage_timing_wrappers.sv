// Synthesis-only tops for measuring one imul pipeline stage at a time.
// Each wrapper places registers immediately before and after the selected
// stage, matching the stage boundaries in riscv_core while keeping the other
// two multiplier stages out of its implementation.

module imul_cycle1_timing_wrapper (
    input  logic             clk,
    input  riscv::ctrl_t     ctrl_i,
    input  logic [riscv::XLEN-1:0] op1_data_i,
    input  logic [riscv::XLEN-1:0] op2_data_i,
    output logic [imul_pkg::MAX_HEIGHT[0]-1:0] imul_cycle1_o [imul_pkg::PP_WIDTH-1:0]
);
    import riscv::*;
    import imul_pkg::*;

    ctrl_t stage0_ctrl_q;
    logic [XLEN-1:0] stage0_op1_q, stage0_op2_q;
    logic [MAX_HEIGHT[0]-1:0] stage1_q [PP_WIDTH-1:0];
    logic [MAX_HEIGHT[0]-1:0] stage1_d [PP_WIDTH-1:0];

    imul_cycle1 u_imul_cycle1 (
        .ctrl_i        (stage0_ctrl_q),
        .op1_data_i    (stage0_op1_q),
        .op2_data_i    (stage0_op2_q),
        .imul_cycle1_o (stage1_d)
    );

    always_ff @(posedge clk) begin
        stage0_ctrl_q <= ctrl_i;
        stage0_op1_q  <= op1_data_i;
        stage0_op2_q  <= op2_data_i;
        stage1_q      <= stage1_d;
    end

    assign imul_cycle1_o = stage1_q;
endmodule : imul_cycle1_timing_wrapper

module imul_cycle2_timing_wrapper (
    input  logic             clk,
    input  logic [imul_pkg::MAX_HEIGHT[0]-1:0] imul_cycle1_i [imul_pkg::PP_WIDTH-1:0],
    output logic [imul_pkg::MAX_HEIGHT[6]-1:0] imul_cycle2_o [imul_pkg::PP_WIDTH-1:0]
);
    import imul_pkg::*;

    logic [MAX_HEIGHT[0]-1:0] stage1_q [PP_WIDTH-1:0];
    logic [MAX_HEIGHT[6]-1:0] stage2_q [PP_WIDTH-1:0];
    logic [MAX_HEIGHT[6]-1:0] stage2_d [PP_WIDTH-1:0];

    imul_cycle2 u_imul_cycle2 (
        .imul_cycle1_i (stage1_q),
        .imul_cycle2_o (stage2_d)
    );

    always_ff @(posedge clk) begin
        stage1_q <= imul_cycle1_i;
        stage2_q <= stage2_d;
    end

    assign imul_cycle2_o = stage2_q;
endmodule : imul_cycle2_timing_wrapper

module imul_cycle3_timing_wrapper (
    input  logic             clk,
    input  riscv::ctrl_t     ctrl_i,
    input  logic [imul_pkg::MAX_HEIGHT[6]-1:0] imul_cycle2_i [imul_pkg::PP_WIDTH-1:0],
    output logic [riscv::XLEN-1:0] imul_res_o
);
    import riscv::*;
    import imul_pkg::*;

    ctrl_t stage2_ctrl_q;
    logic [MAX_HEIGHT[6]-1:0] stage2_q [PP_WIDTH-1:0];
    logic [XLEN-1:0] stage3_q, stage3_d;

    imul_cycle3 u_imul_cycle3 (
        .ctrl_i        (stage2_ctrl_q),
        .imul_cycle2_i (stage2_q),
        .imul_res_o    (stage3_d)
    );

    always_ff @(posedge clk) begin
        stage2_ctrl_q <= ctrl_i;
        stage2_q      <= imul_cycle2_i;
        stage3_q      <= stage3_d;
    end

    assign imul_res_o = stage3_q;
endmodule : imul_cycle3_timing_wrapper
