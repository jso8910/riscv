import riscv::*;

module memory_controller (
    input logic [XLEN-1:0]  data_i,
    input ctrl_t            ctrl_i,
    input logic             commit_i,
    output logic [XLEN-1:0] data_o,
    output logic [7:0]      we_o
);
    logic sign_extend;
    logic [XLEN-1:0] byte_read, half_read, word_read, double_read;

    assign sign_extend = ctrl_i.mem_signed == MEM_SIGNED;
    assign byte_read = {{(XLEN-8){data_i[7] & sign_extend}}, data_i[7:0]};
    assign half_read = {{(XLEN-16){data_i[15] & sign_extend}}, data_i[15:0]};
    assign word_read = {{(XLEN-32){data_i[31] & sign_extend}}, data_i[31:0]};
    assign double_read = data_i;

    always_comb begin
        // Default: no writes
        we_o = '0;
        if (commit_i && ctrl_i.mem_write) begin
            case (ctrl_i.mem_size)
                MEM_BYTE : we_o = 8'b0000_0001;
                MEM_HALF : we_o = 8'b0000_0011;
                MEM_WORD : we_o = 8'b0000_1111;
                MEM_DOUBLE : we_o = 8'b1111_1111;
                MEM_NONE : we_o = '0;
                default : $fatal(1);
            endcase
        end

        // Default: no read
        data_o = '0;
        if (ctrl_i.mem_read) begin
            case (ctrl_i.mem_size)
                MEM_BYTE : data_o = byte_read;
                MEM_HALF : data_o = half_read;
                MEM_WORD : data_o = word_read;
                MEM_DOUBLE : data_o = double_read;
                MEM_NONE : data_o = '0;
                default : $fatal(1);
            endcase
        end
    end
endmodule : memory_controller
