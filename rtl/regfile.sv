import riscv::*;

module regfile (
    input logic                  clk,
    input logic                  rst_n,
    input logic [REG_ADDR_W-1:0] rs1_addr_i,
    input logic [REG_ADDR_W-1:0] rs2_addr_i,
    input logic [REG_ADDR_W-1:0] rd_addr_i,
    input logic                  reg_write_i,
    // input wb_sel_t               wb_sel_i,
    input logic                  commit_i,
    input logic [XLEN-1:0]       rd_data_i,
    // input logic [XLEN-1:0]       alu_i,
    // input logic [XLEN-1:0]       mem_i,
    // input logic [XLEN-1:0]       pc_i,
    // input logic [XLEN-1:0]       imm_i,
    // input logic [XLEN-1:0]       csr_i,
    output logic [XLEN-1:0]      rs1_data_o,
    output logic [XLEN-1:0]      rs2_data_o
);
    logic [XLEN-1:0] regs [0:NUM_REGS - 1];

    // Register read
    assign rs1_data_o = (rs1_addr_i == X0) ? '0 : regs[rs1_addr_i];
    assign rs2_data_o = (rs2_addr_i == X0) ? '0 : regs[rs2_addr_i];

    // Register write logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            for (int i = 0; i < NUM_REGS; i++)
                regs[i] <= '0;
        end else begin
            // x0 is hardcoded to be the value 0
            if (commit_i && reg_write_i && rd_addr_i != X0)
                regs[rd_addr_i] <= rd_data_i;
        end
    end

    // always_comb begin
    //     value_to_write = '0;
    //     case (wb_sel_i)
    //         WB_ALU : value_to_write = alu_i;
    //         WB_MEM : value_to_write = mem_i;
    //         WB_IMM : value_to_write = imm_i;
    //         WB_PC_PLUS_4 : value_to_write = pc_i + PC_INC;
    //         WB_CSR : value_to_write = csr_i;
    //         default : $fatal(1);
    //     endcase
    // end
endmodule
