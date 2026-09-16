`timescale 1ns/1ps

import riscv::*;
import imul_pkg::*;

module tb_booth_encoder_radix4;
    localparam int RANDOM_TESTS = 1000;

    logic signed [XLEN:0]       multiplicand;
    logic [2:0]                  code;
    logic signed [PP_WIDTH-1:0] partial;

    int tests_run;
    int tests_failed;

    booth_encoder_radix4 dut (
        .multiplicand_i(multiplicand),
        .code_i(code),
        .partial_o(partial)
    );

    function automatic logic signed [PP_WIDTH-1:0] expected_partial(
        input logic signed [XLEN:0] multiplicand_in,
        input logic [2:0]            code_in
    );
        logic signed [PP_WIDTH-1:0] multiplicand_extended;
        begin
            multiplicand_extended = multiplicand_in;
            case (code_in)
                3'b000, 3'b111: expected_partial = '0;
                3'b001, 3'b010: expected_partial = multiplicand_extended;
                3'b011:         expected_partial = multiplicand_extended <<< 1;
                3'b100:         expected_partial = -(multiplicand_extended <<< 1);
                3'b101, 3'b110: expected_partial = -multiplicand_extended;
                default:         expected_partial = 'x;
            endcase
        end
    endfunction

    task automatic check(
        input string                    name,
        input logic signed [XLEN:0]     multiplicand_in,
        input logic [2:0]               code_in
    );
        logic signed [PP_WIDTH-1:0] expected;
        begin
            multiplicand = multiplicand_in;
            code = code_in;
            expected = expected_partial(multiplicand_in, code_in);
            #1;

            tests_run++;
            if (partial !== expected) begin
                tests_failed++;
                $fatal(1, "%s: multiplicand=0x%017h code=%03b expected=0x%033h got=0x%033h",
                       name, multiplicand_in, code_in, expected, partial);
            end
        end
    endtask

    initial begin
        tests_run = 0;
        tests_failed = 0;

        // Exercise all eight recoding values, including both encodings of 0,
        // +M, and -M.
        check("000 encodes zero", 65'sh0_0123_4567_89ab_cdef, 3'b000);
        check("001 encodes plus one", 65'sh0_0123_4567_89ab_cdef, 3'b001);
        check("010 also encodes plus one", -65'sd37, 3'b010);
        check("011 encodes plus two", 65'sh0_0123_4567_89ab_cdef, 3'b011);
        check("100 encodes minus two", -65'sd37, 3'b100);
        check("101 encodes minus one", 65'sh0_0123_4567_89ab_cdef, 3'b101);
        check("110 also encodes minus one", -65'sd37, 3'b110);
        check("111 encodes zero", -65'sd37, 3'b111);

        // Boundary values verify sign extension and the 2*M path.
        check("largest positive times two", 65'sh0_ffff_ffff_ffff_ffff, 3'b011);
        check("most negative times two", 65'sh1_0000_0000_0000_0000, 3'b011);
        check("negated most negative", 65'sh1_0000_0000_0000_0000, 3'b101);

        for (int unsigned i = 0; i < RANDOM_TESTS; i++) begin
            check($sformatf("random_%0d", i),
                  {$urandom(), $urandom(), $urandom()}, $urandom_range(0, 7));
        end

        if (tests_failed == 0) begin
            $display("tb_booth_encoder_radix4: all %0d tests passed", tests_run);
            $finish;
        end else begin
            $fatal(1, "tb_booth_encoder_radix4: %0d of %0d tests failed",
                   tests_failed, tests_run);
        end
    end
endmodule : tb_booth_encoder_radix4
