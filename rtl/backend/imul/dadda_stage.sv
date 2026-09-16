// One carry-save reduction layer for a Dadda multiplier.
//
// Bits are column-packed: columns_i[column][slot] has weight 2**column.
// INPUT_COLUMN_HEIGHTS gives the number of live input slots in each column;
// slots above that height are ignored. The module packs output bits from
// slot zero upward and ties the remaining output slots to zero.
module dadda_stage #(
    parameter int WIDTH         = 130,
    parameter int INPUT_HEIGHT  = 33,
    parameter int OUTPUT_HEIGHT = 28,
    parameter int HEIGHT_BITS   = $clog2(INPUT_HEIGHT + 1),
    parameter logic [WIDTH * HEIGHT_BITS - 1:0] INPUT_COLUMN_HEIGHTS =
        {WIDTH{HEIGHT_BITS'(INPUT_HEIGHT)}}
) (
    input  logic [INPUT_HEIGHT-1:0]  columns_i [WIDTH-1:0],
    output logic [OUTPUT_HEIGHT-1:0] columns_o [WIDTH-1:0]
);
    // These functions are evaluated at elaboration time. They calculate the
    // compressor plan for the requested column by replaying the static plan
    // from column zero. Saved carries affect the plan, but do not create a
    // combinational carry chain: they are outputs of this stage only.
    // None of these functions should appear in runtime expressions, as they are very costly
    // when simulated through Verilator.
    function automatic int input_height_at(input int column);
        begin
            input_height_at = int'(
                INPUT_COLUMN_HEIGHTS[column * HEIGHT_BITS +: HEIGHT_BITS]);
        end
    endfunction

    function automatic int full_adders_at(input int requested_column);
        int saved_carries;
        int input_height;
        int excess;
        int full_adders;
        int half_adders;
        begin
            saved_carries = 0;
            full_adders = 0;
            // For each column, calculate the number of full adders and half adders at each row.
            // This is contingent on the height of the row and the number of saved carries coming
            // into the row. For the 0th row, the number of carries coming into the row is 0.
            // So, if input_height_at(0) = 29, the excess would be 29 + 0 - 28 = 1, leading to one
            // half adder (1 % 2 == 0) and 0 full adders (0 / 2 == 0).
            for (int column = 0; column <= requested_column; column++) begin
                input_height = input_height_at(column);
                excess = input_height + saved_carries - OUTPUT_HEIGHT;
                full_adders = (excess > 0) ? excess / 2 : 0;
                half_adders = (excess > 0) ? excess % 2 : 0;
                saved_carries = full_adders + half_adders;
            end
            // Once we've reached our column, we've achieved the correct number of full adders.
            full_adders_at = full_adders;
        end
    endfunction

    function automatic int half_adders_at(input int requested_column);
        int saved_carries;
        int input_height;
        int excess;
        int full_adders;
        int half_adders;
        begin
            // Same logic as the full adder function
            saved_carries = 0;
            half_adders = 0;
            for (int column = 0; column <= requested_column; column++) begin
                input_height = input_height_at(column);
                excess = input_height + saved_carries - OUTPUT_HEIGHT;
                full_adders = (excess > 0) ? excess / 2 : 0;
                half_adders = (excess > 0) ? excess % 2 : 0;
                saved_carries = full_adders + half_adders;
            end
            half_adders_at = half_adders;
        end
    endfunction

    function automatic int incoming_carries_at(input int column);
        begin
            if (column == 0) begin
                incoming_carries_at = 0;
            end else begin
                incoming_carries_at = full_adders_at(column - 1) +
                                      half_adders_at(column - 1);
            end
        end
    endfunction

    // The number of output bits which come from this column — that is, excluding any carry bits. So
    // a column may have 28 rows of height, but if 5 come from carry propagation, the local height
    // is 23.
    function automatic int local_height_at(input int column);
        begin
            local_height_at = input_height_at(column) -
                              2 * full_adders_at(column) -
                              half_adders_at(column);
        end
    endfunction

    function automatic int output_height_at(input int column);
        begin
            output_height_at = local_height_at(column) +
                               incoming_carries_at(column);
        end
    endfunction

    generate
        for (genvar column = 0; column < WIDTH; column++) begin : columns
            localparam int INPUTS       = input_height_at(column);
            localparam int NUM_FULL     = full_adders_at(column);
            localparam int NUM_HALF     = half_adders_at(column);
            localparam int LOCAL_HEIGHT = local_height_at(column);
            localparam int OUTPUTS      = output_height_at(column);
            localparam int NEXT_LOCAL_HEIGHT =
                (column < WIDTH - 1) ? local_height_at(column + 1) : 0;

            initial begin
                if (INPUTS > INPUT_HEIGHT || INPUTS < 0 ||
                    3 * NUM_FULL + 2 * NUM_HALF > INPUTS ||
                    LOCAL_HEIGHT < 0 || OUTPUTS > OUTPUT_HEIGHT) begin
                    $fatal(1, "Invalid Dadda plan at column %0d", column);
                end
            end

            // Full-adder sum outputs occupy the first local output slots.
            for (genvar adder = 0; adder < NUM_FULL; adder++) begin : full_adders
                logic [2:0] inputs;
                logic       carry_save;

                assign inputs = columns_i[column][3 * adder +: 3];
                assign columns_o[column][adder] = ^inputs;
                assign carry_save = (inputs[0] & inputs[1]) |
                                    (inputs[0] & inputs[2]) |
                                    (inputs[1] & inputs[2]);

                // The last column just overflows
                if (column < WIDTH - 1) begin : save_carry
                    // We need to put this carry bit in the next column ABOVE the local bits
                    assign columns_o[column + 1][NEXT_LOCAL_HEIGHT + adder] =
                        carry_save;
                end
            end

            // A half adder is used whenever the current column needs an odd
            // one-bit reduction after including saved carries from the left.
            for (genvar adder = 0; adder < NUM_HALF; adder++) begin : half_adders
                logic [1:0] inputs;
                logic       carry_save;

                assign inputs = columns_i[column][3 * NUM_FULL + 2 * adder +: 2];
                assign columns_o[column][NUM_FULL + adder] = ^inputs;
                assign carry_save = inputs[0] & inputs[1];

                if (column < WIDTH - 1) begin : save_carry
                    assign columns_o[column + 1][NEXT_LOCAL_HEIGHT +
                                                 NUM_FULL + adder] = carry_save;
                end
            end

            // Preserve locally uncompressed bits after the compressor inputs.
            for (genvar bit_slot = 0;
                 bit_slot < INPUTS - 3 * NUM_FULL - 2 * NUM_HALF;
                 bit_slot++) begin : pass_through
                assign columns_o[column][NUM_FULL + NUM_HALF + bit_slot] =
                    columns_i[column][3 * NUM_FULL + 2 * NUM_HALF + bit_slot];
            end

            // Output slots above the planned height are structural zeroes.
            for (genvar bit_slot = OUTPUTS;
                 bit_slot < OUTPUT_HEIGHT;
                 bit_slot++) begin : clear_unused
                assign columns_o[column][bit_slot] = 1'b0;
            end
        end
    endgenerate
endmodule : dadda_stage
