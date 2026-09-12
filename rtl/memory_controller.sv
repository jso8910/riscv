import riscv::*;

module memory_controller (
    input logic [XLEN-1:0]  data_i,
    input logic [XLEN-1:0]  mtime_i,
    input logic [XLEN-1:0]  mtimecmp_i,
    input mem_req_t         mem_req_i,
    input logic             commit_i,
    output mem_res_t        res_o,
    output logic [7:0]      we_o,
    output logic            mtime_we_o,
    output logic            mtimecmp_we_o
);
    logic sign_extend;
    logic [XLEN-1:0] byte_read, half_read, word_read, double_read;

    assign sign_extend = mem_req_i.mem_signed == MEM_SIGNED;
    assign byte_read = {{(XLEN-8){data_i[7] & sign_extend}}, data_i[7:0]};
    assign half_read = {{(XLEN-16){data_i[15] & sign_extend}}, data_i[15:0]};
    assign word_read = {{(XLEN-32){data_i[31] & sign_extend}}, data_i[31:0]};
    assign double_read = data_i;

    always_comb begin
        // Default: no writes
        we_o = '0;
        mtime_we_o = '0;
        mtimecmp_we_o = '0;
        if (mem_req_i.valid) begin
            if (commit_i && mem_req_i.op == MWRITE) begin
                // Since PMA only allows doubleword aligned accesses in the MMIO region, this is valid
                // as a check --- eg addr_i = MTIME_ADDR + 1 is illegal
                case (mem_req_i.address)
                    MTIME_ADDR : mtime_we_o = '1;
                    MTIMECMP_ADDR : mtimecmp_we_o = '1;
                    default : begin
                        case (mem_req_i.size)
                            MEM_BYTE : we_o = 8'b0000_0001;
                            MEM_HALF : we_o = 8'b0000_0011;
                            MEM_WORD : we_o = 8'b0000_1111;
                            MEM_DOUBLE : we_o = 8'b1111_1111;
                            MEM_NONE : we_o = '0;
                            default : $fatal(1);
                        endcase
                    end
                endcase
            end
        end
    end

    always_comb begin
        res_o.valid = '0;
        res_o.data = '0;

        if (mem_req_i.valid) begin
            // Default: no read
            if (mem_req_i.op == MREAD || mem_req_i.op == MFETCH) begin
                res_o.valid = '1;
                case (mem_req_i.address)
                    MTIME_ADDR : res_o.data = mtime_i;
                    MTIMECMP_ADDR : res_o.data = mtimecmp_i;
                    default : begin
                        case (mem_req_i.size)
                            MEM_BYTE : res_o.data = byte_read;
                            MEM_HALF : res_o.data = half_read;
                            MEM_WORD : res_o.data = word_read;
                            MEM_DOUBLE : res_o.data = double_read;
                            MEM_NONE : res_o.data = '0;
                            default : $fatal(1);
                        endcase
                    end
                endcase
            end
        end
    end
endmodule : memory_controller
