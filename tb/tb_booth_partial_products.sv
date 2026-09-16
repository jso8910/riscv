`timescale 1ns/1ps

import riscv::*;
import imul_pkg::*;

module tb_booth_partial_products;
    localparam int RANDOM_TESTS = 1000;

    logic signed [XLEN:0] multiplicand;
    logic signed [XLEN:0] multiplier;
    logic signed [PP_WIDTH-1:0] partial_products [NUM_PP-1:0];
    logic [NUM_PP-1:0] dadda_columns [PP_WIDTH-1:0];

    int tests_run;
    int tests_failed;

    booth_partial_products dut (
        .op1_data_i(multiplicand),
        .op2_data_i(multiplier),
        .partial_products_o(partial_products)
    );

    booth_partial_products_to_columns u_booth_partial_products_to_columns (
        .partial_products_i(partial_products),
        .columns_o(dadda_columns)
    );

    function automatic logic signed [PP_WIDTH-1:0] recoded_multiplicand(
        input logic signed [XLEN:0] multiplicand_in,
        input logic [2:0]            code
    );
        logic signed [PP_WIDTH-1:0] multiplicand_extended;
        begin
            multiplicand_extended = multiplicand_in;
            case (code)
                3'b000, 3'b111: recoded_multiplicand = '0;
                3'b001, 3'b010: recoded_multiplicand = multiplicand_extended;
                3'b011:         recoded_multiplicand = multiplicand_extended <<< 1;
                3'b100:         recoded_multiplicand = -(multiplicand_extended <<< 1);
                3'b101, 3'b110: recoded_multiplicand = -multiplicand_extended;
                default:         recoded_multiplicand = 'x;
            endcase
        end
    endfunction

    function automatic logic signed [PP_WIDTH-1:0] expected_product(
        input logic signed [XLEN:0] multiplicand_in,
        input logic signed [XLEN:0] multiplier_in
    );
        logic signed [PP_WIDTH-1:0] multiplicand_extended;
        logic signed [PP_WIDTH-1:0] multiplier_extended;
        begin
            multiplicand_extended = multiplicand_in;
            multiplier_extended = multiplier_in;
            expected_product = multiplicand_extended * multiplier_extended;
        end
    endfunction

    task automatic check(
        input string                    name,
        input logic signed [XLEN:0]     multiplicand_in,
        input logic signed [XLEN:0]     multiplier_in
    );
        logic signed [XLEN+1:-1] padded_multiplier;
        logic signed [PP_WIDTH-1:0] expected_pp;
        logic signed [PP_WIDTH-1:0] partial_sum;
        logic expected_column_bit;
        begin
            multiplicand = multiplicand_in;
            multiplier = multiplier_in;
            padded_multiplier = $signed({multiplier_in[XLEN], multiplier_in, 1'b0});
            #1;

            for (int column = 0; column < PP_WIDTH; column++) begin
                for (int row = 0; row < NUM_PP; row++) begin
                    expected_column_bit = (2 * row <= column) ?
                                          partial_products[row][column] : 1'b0;
                    tests_run++;
                    if (dadda_columns[column][row] !== expected_column_bit) begin
                        tests_failed++;
                        $fatal(1, "%s, column %0d slot %0d: expected %b got %b",
                               name, column, row, expected_column_bit,
                               dadda_columns[column][row]);
                    end
                end
            end

            partial_sum = '0;
            for (int i = 0; i < NUM_PP; i++) begin
                expected_pp = recoded_multiplicand(
                    multiplicand_in, padded_multiplier[2*i + 1 -: 3]) <<< (2*i);
                tests_run++;
                if (partial_products[i] !== expected_pp) begin
                    tests_failed++;
                    $fatal(1, "%s, partial product %0d: expected=0x%033h got=0x%033h",
                           name, i, expected_pp, partial_products[i]);
                end
                partial_sum = partial_sum + partial_products[i];
            end

            tests_run++;
            if (partial_sum !== expected_product(multiplicand_in, multiplier_in)) begin
                tests_failed++;
                $fatal(1, "%s, partial-product sum: expected=0x%033h got=0x%033h",
                       name, expected_product(multiplicand_in, multiplier_in), partial_sum);
            end
        end
    endtask

    initial begin
        tests_run = 0;
        tests_failed = 0;

        check("zero multiplicand", '0, 65'sh0_1234_5678_9abc_def0);
        check("zero multiplier", 65'sh0_1234_5678_9abc_def0, '0);
        check("one times one", 65'sd1, 65'sd1);
        check("positive times negative", 65'sd123456789, -65'sd987654321);
        check("negative times positive", -65'sd123456789, 65'sd987654321);
        check("negative times negative", -65'sd123456789, -65'sd987654321);
        check("largest positive operands", 65'sh0_ffff_ffff_ffff_ffff,
              65'sh0_ffff_ffff_ffff_ffff);
        check("most negative operands", 65'sh1_0000_0000_0000_0000,
              65'sh1_0000_0000_0000_0000);
        check("most negative times largest positive", 65'sh1_0000_0000_0000_0000,
              65'sh0_ffff_ffff_ffff_ffff);
        check("largest positive times most negative", 65'sh0_ffff_ffff_ffff_ffff,
              65'sh1_0000_0000_0000_0000);
        check("alternating operand bits", 65'sh0_5555_5555_5555_5555,
              65'sh1_5555_5555_5555_5555);

        for (int unsigned i = 0; i < RANDOM_TESTS; i++) begin
            check($sformatf("random_%0d", i),
                  {$urandom(), $urandom(), $urandom()},
                  {$urandom(), $urandom(), $urandom()});
        end

        if (tests_failed == 0) begin
            $display("tb_booth_partial_products: all %0d checks passed", tests_run);
            $finish;
        end else begin
            $fatal(1, "tb_booth_partial_products: %0d of %0d checks failed",
                   tests_failed, tests_run);
        end
    end
endmodule : tb_booth_partial_products
