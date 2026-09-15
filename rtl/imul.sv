import riscv::*;

package imul;
    localparam int PP_WIDTH = 2 * (XLEN + 1);   // 130
    localparam int NUM_PP   = (XLEN + 2) / 2;   // 33
endpackage
import imul::*;
// 3 stage pipelined integer multiplier
// Stage 1: Partial product generation with radix-4 booth encoding
// Stage 2: Dadda tree reduction
// Stage 3: Final addition stage, MUL/MULH/MULW selection
// This multiplier is actually XLEN+1 bits to allow for sign extending.

module imul (
    input logic             clk,
    input logic             rst_n,
    input ctrl_t            ctrl_i,
    input logic [XLEN-1:0]  op1_data_i,
    input logic [XLEN-1:0]  op2_data_i,
    output logic [XLEN-1:0] res_o
);

endmodule : imul

module booth_encoder_radix4 (
    input logic signed [XLEN:0]             multiplicand_i,
    input logic [2:0]                       code_i,         // 3 bit sliding window (bits i-1, i, and i+1)
    output logic signed [PP_WIDTH-1:0] partial_o
);
    logic signed [XLEN+1:0] multiplicand_x2;

    // shift left by 1 bit
    assign multiplicand_x2 = $signed({multiplicand_i, 1'b0});

    always_comb begin
        case (code_i)
            3'b000, 3'b111 : partial_o = '0;
            3'b001, 3'b010 : partial_o = PP_WIDTH'(multiplicand_i);
            3'b011         : partial_o = PP_WIDTH'(multiplicand_x2);
            3'b100         : partial_o = -PP_WIDTH'(multiplicand_x2);
            3'b101, 3'b110 : partial_o = -PP_WIDTH'(multiplicand_i);
            default: $fatal(1, "Unreachable");
        endcase
    end
endmodule : booth_encoder_radix4

module booth_partial_products (
    input logic signed [XLEN:0]  op1_data_i,
    input logic signed [XLEN:0]  op2_data_i,
    // Radix 4 booth encoding yields ceil(n/2). Here, n = XLEN+1 or 65. To get ceil, we do (n+1)/2,
    // where / is the floor integer division operator.
    // Note that the partial products are a full 130 bits wide. However, only 66 bits at most are
    // meaningful (65 bits for M, then an extra bit for 2M), which should be detected by the
    // synthesizer. The remaining bits are either 0s or sign extensions
    // TODO: verify this happens
    output logic signed [PP_WIDTH-1:0] partial_products_o [NUM_PP-1:0]
);
    logic signed [PP_WIDTH-1:0] partial_products_raw [NUM_PP-1:0];

    // op2 needs to be padded on both sides
    logic signed [XLEN+1:-1] op2_data_padded;
    assign op2_data_padded = $signed({op2_data_i[XLEN], op2_data_i, 1'b0});

    generate
        for (genvar i = 0; i < NUM_PP; i++) begin : ppgen
            booth_encoder_radix4 u_booth_encoder_radix4 (
                .multiplicand_i(op1_data_i),
                .code_i        (op2_data_padded[2*i + 1 : 2*i - 1]),
                .partial_o     (partial_products_raw[i])
            );
            assign partial_products_o[i] = partial_products_raw[i] << (2*i);
        end
    endgenerate
endmodule : booth_partial_products
