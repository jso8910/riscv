import riscv::*;

// Byte addressable little endian SRAM module
module sram #(
    parameter int DWIDTH = 64,
    parameter int NUM_BYTES = DWIDTH / 8,
    parameter int AWIDTH = 64,
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
        for (int i = 0; i < NUM_BYTES; i++) begin
            mem_byte_array[i] = (address_1_i + uintxlen_t'(i) <= END_ADDRESS) && (address_1_i + uintxlen_t'(i) >= START_ADDRESS) ? mem[address_1_i + uintxlen_t'(i)] : 8'b0;
            data_1_o[i * 8 +: 8] = mem_byte_array[i];
        end
        for (int i = 0; i < NUM_BYTES; i++) begin
            mem_byte_array[i] = (address_2_i + uintxlen_t'(i) <= END_ADDRESS) && (address_2_i + uintxlen_t'(i) >= START_ADDRESS) ? mem[address_2_i + uintxlen_t'(i)] : 8'b0;
            data_2_o[i * 8 +: 8] = mem_byte_array[i];
        end
    end

    // Memory write
    always_ff @(posedge clk) begin
        for (int i = 0; i < NUM_BYTES; i++) begin
            if (we_i[i] == 1'b1 && (address_1_i + uintxlen_t'(i) <= END_ADDRESS) && (address_1_i + uintxlen_t'(i) >= START_ADDRESS)) begin
                mem[address_1_i + uintxlen_t'(i)] <= data_i[i * 8 +: 8];
            end
        end
    end
endmodule : sram
