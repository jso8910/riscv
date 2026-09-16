`timescale 1ns/1ps

import riscv::*;
import imul_pkg::*;

module tb_dadda_stage;
    localparam int WIDTH         = PP_WIDTH;
    localparam int INPUT_HEIGHT  = NUM_PP;
    localparam int OUTPUT_HEIGHT = 28;
    localparam int HEIGHT_BITS   = imul_pkg::HEIGHT_BITS;
    localparam int RANDOM_TESTS  = 100;

    localparam logic [WIDTH * HEIGHT_BITS - 1:0] INPUT_COLUMN_HEIGHTS =
        dadda_stage_height_map(0);

    logic [INPUT_HEIGHT-1:0]  columns_i [WIDTH-1:0];
    logic [OUTPUT_HEIGHT-1:0] columns_o [WIDTH-1:0];

    int tests_run;
    int tests_failed;

    dadda_stage #(
        .WIDTH(WIDTH),
        .INPUT_HEIGHT(INPUT_HEIGHT),
        .OUTPUT_HEIGHT(OUTPUT_HEIGHT),
        .HEIGHT_BITS(HEIGHT_BITS),
        .INPUT_COLUMN_HEIGHTS(INPUT_COLUMN_HEIGHTS)
    ) dut (
        .columns_i(columns_i),
        .columns_o(columns_o)
    );

    function automatic logic random_bit;
        logic [31:0] random_word;
        begin
            random_word = $urandom();
            random_bit = random_word[0];
        end
    endfunction

    task automatic check(input string name);
        logic [WIDTH-1:0] input_value;
        logic [WIDTH-1:0] output_value;
        begin
            #1;
            input_value = '0;
            output_value = '0;
            for (int column = 0; column < WIDTH; column++) begin
                for (int slot = 0; slot < INPUT_HEIGHT; slot++) begin
                    input_value = input_value +
                        ({{(WIDTH - 1){1'b0}}, columns_i[column][slot]} << column);
                end
                for (int slot = 0; slot < OUTPUT_HEIGHT; slot++) begin
                    output_value = output_value +
                        ({{(WIDTH - 1){1'b0}}, columns_o[column][slot]} << column);
                end
            end

            tests_run++;
            if (output_value !== input_value) begin
                tests_failed++;
                $fatal(1, "%s: output matrix changed the represented value; expected 0x%033h, got 0x%033h",
                       name, input_value, output_value);
            end
        end
    endtask

    initial begin
        tests_run = 0;
        tests_failed = 0;

        // Verify every elaboration-time map in the complete Dadda schedule.
        for (int stage = 0; stage <= NUM_DADDA_STAGES; stage++) begin
            height_map_t heights;
            int maximum_height;
            int expected_maximum;

            heights = dadda_stage_height_map(stage);
            maximum_height = 0;
            for (int column = 0; column < WIDTH; column++) begin
                int height;
                height = int'(heights[column * HEIGHT_BITS +: HEIGHT_BITS]);
                if (height > maximum_height) begin
                    maximum_height = height;
                end
            end
            expected_maximum = (stage == 0) ? NUM_PP :
                               MAX_HEIGHT[stage - 1];
            tests_run++;
            if (maximum_height != expected_maximum) begin
                tests_failed++;
                $fatal(1, "stage %0d: expected maximum height %0d, got %0d",
                       stage, expected_maximum, maximum_height);
            end
        end

        for (int column = 0; column < WIDTH; column++) begin
            columns_i[column] = '0;
        end
        check("all zeroes");

        for (int column = 0; column < WIDTH; column++) begin
            columns_i[column] = '0;
            for (int slot = 0;
                 slot < INPUT_COLUMN_HEIGHTS[column * HEIGHT_BITS +: HEIGHT_BITS];
                 slot++) begin
                columns_i[column][slot] = 1'b1;
            end
        end
        check("all ones");

        for (int test = 0; test < RANDOM_TESTS; test++) begin
            for (int column = 0; column < WIDTH; column++) begin
                columns_i[column] = '0;
                for (int slot = 0;
                     slot < INPUT_COLUMN_HEIGHTS[column * HEIGHT_BITS +: HEIGHT_BITS];
                     slot++) begin
                    columns_i[column][slot] = random_bit();
                end
            end
            check($sformatf("random_%0d", test));
        end

        if (tests_failed == 0) begin
            $display("tb_dadda_stage: all %0d tests passed", tests_run);
            $finish;
        end else begin
            $fatal(1, "tb_dadda_stage: %0d of %0d tests failed", tests_failed, tests_run);
        end
    end
endmodule : tb_dadda_stage
