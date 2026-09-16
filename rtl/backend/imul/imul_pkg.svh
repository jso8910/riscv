import riscv::*;

package imul_pkg;
    localparam int PP_WIDTH = 2 * (XLEN + 1);   // 130
    localparam int NUM_PP   = (XLEN + 2) / 2;   // 33
    localparam int HEIGHT_BITS = $clog2(NUM_PP + 1);

    typedef logic [PP_WIDTH * HEIGHT_BITS - 1:0] height_map_t;

    // Dadda maximum height sequence
    localparam int MAX_HEIGHT [0:7] = {28, 19, 13, 9, 6, 4, 3, 2};
    localparam int NUM_DADDA_STAGES = $size(MAX_HEIGHT);

    // Stage zero is the column-height map for the shifted Booth rows.  Each
    // row begins at bit position 2*row, so the live height rises by one every
    // two columns until all NUM_PP rows are present.
    function automatic height_map_t booth_height_map();
        height_map_t heights;
        int height;
        begin
            heights = '0;
            for (int column = 0; column < PP_WIDTH; column++) begin
                height = column / 2 + 1;
                if (height > NUM_PP) begin
                    height = NUM_PP;
                end
                heights[column * HEIGHT_BITS +: HEIGHT_BITS] = HEIGHT_BITS'(height);
            end
            booth_height_map = heights;
        end
    endfunction

    // Derive one output height map from an input map and a Dadda target.
    // The calculation matches dadda_stage: carries produced in column j-1
    // occupy slots in column j's output, but are not consumed until the next
    // Dadda stage.
    function automatic height_map_t dadda_next_height_map(
        input height_map_t input_heights,
        input int          output_height
    );
        height_map_t output_heights;
        int saved_carries;
        int input_height;
        int excess;
        int full_adders;
        int half_adders;
        int local_height;
        begin
            output_heights = '0;
            saved_carries = 0;
            for (int column = 0; column < PP_WIDTH; column++) begin
                input_height = int'(
                    input_heights[column * HEIGHT_BITS +: HEIGHT_BITS]);
                excess = input_height + saved_carries - output_height;
                full_adders = (excess > 0) ? excess / 2 : 0;
                half_adders = (excess > 0) ? excess % 2 : 0;
                local_height = input_height - 2 * full_adders - half_adders;
                output_heights[column * HEIGHT_BITS +: HEIGHT_BITS] =
                    unsigned'(HEIGHT_BITS'(local_height + saved_carries));
                saved_carries = full_adders + half_adders;
            end
            dadda_next_height_map = output_heights;
        end
    endfunction

    // Returns the structural input map for a numbered Dadda stage:
    //   0: Booth rows (maximum height 33)
    //   1: after 33 -> 28
    //   2: after 28 -> 19
    //   ...
    //   8: after 3 -> 2
    function automatic height_map_t dadda_stage_height_map(input int stage);
        height_map_t heights;
        begin
            heights = booth_height_map();
            if (stage < 0 || stage > NUM_DADDA_STAGES) begin
                heights = '0;
            end else begin
                for (int reduction = 0; reduction < stage; reduction++) begin
                    heights = dadda_next_height_map(
                        heights, MAX_HEIGHT[reduction]);
                end
            end
            dadda_stage_height_map = heights;
        end
    endfunction
endpackage
