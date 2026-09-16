import riscv::*;
import imul_pkg::*;
// 3 stage pipelined integer multiplier
// Stage 1: Partial product generation with radix-4 booth encoding
// Stage 2: Dadda tree reduction
// Stage 3: Final addition stage, MUL/MULH/MULW selection
// This multiplier is actually XLEN+1 bits to allow for sign extending.
// The exact cycles for the pipeline vary, but the current plan is this:
// Cycle 1: Partial product + 2 stages of Dadda reduction (33 -> 19)
// Cycle 2: 4 stages of reduction (19 -> 4)
// Cycle 3: 2 stages of reduction (4 -> 2) + 130 bit adder
// I'll need to perform timing analysis with synthesis to ensure each cycle is actually even.

module imul_cycle1 (
    input ctrl_t                     ctrl_i,
    input logic [XLEN-1:0]           op1_data_i,
    input logic [XLEN-1:0]           op2_data_i,
    output logic [MAX_HEIGHT[1]-1:0] imul_cycle1_o [PP_WIDTH-1:0]
);
    logic signed [XLEN:0] op1_data, op2_data;
    always_comb begin
        case (ctrl_i.mul_op)
            NO_MUL : begin
                // This helps both for simulation (Verilator) and in actual hardware, because it
                // reduces dynamic power consumption by effectively gating all the multiply logic.
                op1_data = '0;
                op2_data = '0;
            end
            OP_MUL : begin
                // Doesn't matter if signed.
                // Also, we don't need to account for MULW because the operands can be the same 64
                // bit unsigned operands.
                op1_data = $signed({1'b0, op1_data_i});
                op2_data = $signed({1'b0, op2_data_i});
            end
            OP_MULH : begin
                // signed * signed
                op1_data = $signed({op1_data_i[63], op1_data_i});
                op2_data = $signed({op2_data_i[63], op2_data_i});
            end
            OP_MULHU : begin
                // unsigned * unsigned
                op1_data = $signed({1'b0, op1_data_i});
                op2_data = $signed({1'b0, op2_data_i});
            end
            OP_MULHSU : begin
                // signed * unsigned
                op1_data = $signed({op1_data_i[63], op1_data_i});
                op2_data = $signed({1'b0, op2_data_i});
            end
            default: begin
                op1_data = $signed({1'b0, op1_data_i});
                op2_data = $signed({1'b0, op2_data_i});
                assert (1'b0);
            end
        endcase
    end

    // Booth reduction
    logic signed [PP_WIDTH-1:0] partial_products [NUM_PP-1:0];
    booth_partial_products u_booth_partial_products (
        .op1_data_i        (op1_data),
        .op2_data_i        (op2_data),
        .partial_products_o(partial_products)
    );

    logic [NUM_PP-1:0] dadda_columns_0 [PP_WIDTH-1:0];
    booth_partial_products_to_columns booth_partial_products_to_columns (
        .partial_products_i(partial_products),
        .columns_o         (dadda_columns_0)
    );

    // Stage 1
    logic [MAX_HEIGHT[0]-1:0] dadda_columns_1 [PP_WIDTH-1:0];
    dadda_stage #(
        .INPUT_HEIGHT        (NUM_PP),
        .OUTPUT_HEIGHT       (MAX_HEIGHT[0]),
        .HEIGHT_BITS          (HEIGHT_BITS),
        .INPUT_COLUMN_HEIGHTS(dadda_stage_height_map(0))
     ) u_dadda_stage_3 (
        .columns_i(dadda_columns_0),
        .columns_o(dadda_columns_1)
    );

    // Stage 2
    logic [MAX_HEIGHT[1]-1:0] dadda_columns_2 [PP_WIDTH-1:0];
    dadda_stage #(
        .INPUT_HEIGHT        (MAX_HEIGHT[0]),
        .OUTPUT_HEIGHT       (MAX_HEIGHT[1]),
        .HEIGHT_BITS          (HEIGHT_BITS),
        .INPUT_COLUMN_HEIGHTS(dadda_stage_height_map(1))
     ) u_dadda_stage_2 (
        .columns_i(dadda_columns_1),
        .columns_o(dadda_columns_2)
    );

    assign imul_cycle1_o = dadda_columns_2;
endmodule : imul_cycle1

module imul_cycle2 (
    input logic [MAX_HEIGHT[1]-1:0] imul_cycle1_i [PP_WIDTH-1:0],
    output logic [MAX_HEIGHT[5]-1:0] imul_cycle2_o [PP_WIDTH-1:0]
);
    // Stage 3
    logic [MAX_HEIGHT[2]-1:0] dadda_columns_3 [PP_WIDTH-1:0];
    dadda_stage #(
        .INPUT_HEIGHT        (MAX_HEIGHT[1]),
        .OUTPUT_HEIGHT       (MAX_HEIGHT[2]),
        .HEIGHT_BITS          (HEIGHT_BITS),
        .INPUT_COLUMN_HEIGHTS(dadda_stage_height_map(2))
     ) u_dadda_stage_3 (
        .columns_i(imul_cycle1_i),
        .columns_o(dadda_columns_3)
    );

    // Stage 4
    logic [MAX_HEIGHT[3]-1:0] dadda_columns_4 [PP_WIDTH-1:0];
    dadda_stage #(
        .INPUT_HEIGHT        (MAX_HEIGHT[2]),
        .OUTPUT_HEIGHT       (MAX_HEIGHT[3]),
        .HEIGHT_BITS          (HEIGHT_BITS),
        .INPUT_COLUMN_HEIGHTS(dadda_stage_height_map(3))
     ) u_dadda_stage_4 (
        .columns_i(dadda_columns_3),
        .columns_o(dadda_columns_4)
    );

    // Stage 5
    logic [MAX_HEIGHT[4]-1:0] dadda_columns_5 [PP_WIDTH-1:0];
    dadda_stage #(
        .INPUT_HEIGHT        (MAX_HEIGHT[3]),
        .OUTPUT_HEIGHT       (MAX_HEIGHT[4]),
        .HEIGHT_BITS          (HEIGHT_BITS),
        .INPUT_COLUMN_HEIGHTS(dadda_stage_height_map(4))
     ) u_dadda_stage_5 (
        .columns_i(dadda_columns_4),
        .columns_o(dadda_columns_5)
    );

    // Stage 6
    logic [MAX_HEIGHT[5]-1:0] dadda_columns_6 [PP_WIDTH-1:0];
    dadda_stage #(
        .INPUT_HEIGHT        (MAX_HEIGHT[4]),
        .OUTPUT_HEIGHT       (MAX_HEIGHT[5]),
        .HEIGHT_BITS          (HEIGHT_BITS),
        .INPUT_COLUMN_HEIGHTS(dadda_stage_height_map(5))
     ) u_dadda_stage_6 (
        .columns_i(dadda_columns_5),
        .columns_o(dadda_columns_6)
    );

    assign imul_cycle2_o = dadda_columns_6;
endmodule : imul_cycle2

module imul_cycle3 (
    input ctrl_t                    ctrl_i,
    input logic [MAX_HEIGHT[5]-1:0] imul_cycle2_i [PP_WIDTH-1:0],
    output logic [XLEN-1:0]         imul_res_o
);
    // Stage 7
    logic [MAX_HEIGHT[6]-1:0] dadda_columns_7 [PP_WIDTH-1:0];
    dadda_stage #(
        .INPUT_HEIGHT        (MAX_HEIGHT[5]),
        .OUTPUT_HEIGHT       (MAX_HEIGHT[6]),
        .HEIGHT_BITS          (HEIGHT_BITS),
        .INPUT_COLUMN_HEIGHTS(dadda_stage_height_map(6))
     ) u_dadda_stage_7 (
        .columns_i(imul_cycle2_i),
        .columns_o(dadda_columns_7)
    );

    // Stage 8
    logic [MAX_HEIGHT[7]-1:0] dadda_columns_8 [PP_WIDTH-1:0];
    dadda_stage #(
        .INPUT_HEIGHT        (MAX_HEIGHT[6]),
        .OUTPUT_HEIGHT       (MAX_HEIGHT[7]),
        .HEIGHT_BITS          (HEIGHT_BITS),
        .INPUT_COLUMN_HEIGHTS(dadda_stage_height_map(7))
     ) u_dadda_stage_8 (
        .columns_i(dadda_columns_7),
        .columns_o(dadda_columns_8)
    );

    // 130 bit adding reduction
    logic [PP_WIDTH-1:0] dadda_final_row_0;
    logic [PP_WIDTH-1:0] dadda_final_row_1;
    logic [PP_WIDTH-1:0] imul_res_raw;

    generate
        for (genvar column = 0; column < PP_WIDTH; column++) begin : final_rows
            assign dadda_final_row_0[column] = dadda_columns_8[column][0];
            assign dadda_final_row_1[column] = dadda_columns_8[column][1];
        end
    endgenerate

    assign imul_res_raw = dadda_final_row_0 + dadda_final_row_1;

    // Final result generation
    always_comb begin
        case (ctrl_i.mul_op)
            NO_MUL : imul_res_o = '0;
            OP_MUL : begin
                if (ctrl_i.alu_word_op) begin
                    // First 32 bits, sign extended to 64 bits
                    imul_res_o = {{32{imul_res_raw[31]}}, imul_res_raw[31:0]};
                end else begin
                    imul_res_o = imul_res_raw[63:0];
                end
            end
            OP_MULH, OP_MULHU, OP_MULHSU : begin
                imul_res_o = imul_res_raw[127:64];
            end
            default : begin
                imul_res_o = '0;
                assert (1'b0);
            end
        endcase
    end
endmodule : imul_cycle3

// Converts the row-oriented shifted Booth products into the column-packed
// matrix consumed by the first Dadda stage.  Each valid source bit is routed
// directly; slots below a row's 2*i shift are structural zeroes.
// This doesn't actually lead to any extra hardware, it's just transposing the Booth partial
// products output.
module booth_partial_products_to_columns (
    input  logic signed [PP_WIDTH-1:0] partial_products_i [NUM_PP-1:0],
    output logic        [NUM_PP-1:0]   columns_o [PP_WIDTH-1:0]
);
    generate
        for (genvar column = 0; column < PP_WIDTH; column++) begin : columns
            for (genvar row = 0; row < NUM_PP; row++) begin : slots
                if (2 * row <= column) begin : valid_partial_product
                    assign columns_o[column][row] = partial_products_i[row][column];
                end else begin : shifted_out
                    assign columns_o[column][row] = 1'b0;
                end
            end
        end
    endgenerate
endmodule : booth_partial_products_to_columns
