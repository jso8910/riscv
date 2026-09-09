import riscv::*;

// Byte addressable little endian SRAM module
module sram #(
    parameter int DWIDTH = 32,
    parameter int NUM_BYTES = DWIDTH / 8,
    parameter int AWIDTH = 32,
    parameter logic [AWIDTH-1:0] START_ADDRESS = 'h00_00_00_00,
    parameter logic [AWIDTH-1:0] END_ADDRESS = 'h00_00_ff_ff
)(
    input logic clk,
    input logic [AWIDTH-1:0] address_1_i,
    input logic [AWIDTH-1:0] address_2_i,
    input logic [DWIDTH-1:0] data_i,
    input logic [NUM_BYTES-1:0] we_i,
    output logic [DWIDTH-1:0] data_1_o,
    output logic [DWIDTH-1:0] data_2_o
);
    logic [7:0] mem [START_ADDRESS : END_ADDRESS];
    logic [7:0] mem_byte_array [0:NUM_BYTES-1];

    // Memory read
    always_comb begin
        // TODO proper fault handling if address_i is not between START_ADDRESS and END_ADDRESS
        // This should be in some external memory controller, because it's not possible to know if
        // eg address_i + 2 being outside the range is invalid or not from here.
        for (int i = 0; i < NUM_BYTES; i++) begin
            mem_byte_array[i] = (address_1_i + i <= END_ADDRESS) && (address_1_i + i >= START_ADDRESS) ? mem[address_1_i + i] : 8'b0;
            data_1_o[i * 8 +: 8] = mem_byte_array[i];
        end
        for (int i = 0; i < NUM_BYTES; i++) begin
            mem_byte_array[i] = (address_2_i + i <= END_ADDRESS) && (address_2_i + i >= START_ADDRESS) ? mem[address_2_i + i] : 8'b0;
            data_2_o[i * 8 +: 8] = mem_byte_array[i];
        end
    end

    // Memory write
    always_ff @(posedge clk) begin
        // TODO proper fault handling if writes are to illegal locations. Currently it's assumed
        // that this simply won't happen. And wrapping doesn't work because technically wrapping
        // is not correct (since the address after END_ADDRESS is simply a part of another
        // segment of memory).
        for (int i = 0; i < NUM_BYTES; i++) begin
            if (we_i[i] == 1'b1 && (address_1_i + i <= END_ADDRESS) && (address_1_i + i >= START_ADDRESS)) begin
                mem[address_1_i + i] <= data_i[i * 8 +: 8];
            end
        end
    end
endmodule : sram
