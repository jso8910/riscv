import riscv::*;

        // need to figure out how to get the data from the csr
        // i think what i should do is have a separate input in the csr file for the read address
        // but importantly, the thing is, you dont actually need to figure out the faults yet! you
        // can still use ctrl_i for the faults, they'll just be raised after the value is outputted
        // from the csr
        // don't forget to ungate the csr read from illegal_inst (because illegal_inst) will no
        // longer correspond with the current read
        // also dont forget to remove the write value generation logic from the csr and replace it
        // with csr_val_gen.sv in the EX stage

module forwarding_unit (
    input ctrl_t            ex_ctrl_i,
    input logic [XLEN-1:0]  ex_rs1_data_raw_i,
    input logic [XLEN-1:0]  ex_rs2_data_raw_i,
    input logic [XLEN-1:0]  ex_csr_data_raw_i,

    // Forwarding from EX/MEM register
    input logic             mem_valid_i,
    input ctrl_t            mem_ctrl_i,
    input logic [XLEN-1:0]  mem_rd_data_i,

    // Forwarding from MEM/WB register
    input logic             wb_valid_i,
    input ctrl_t            wb_ctrl_i,
    input logic [XLEN-1:0]  wb_rd_data_i,

    // Operand outputs
    output logic [XLEN-1:0] ex_rs1_data_o,
    output logic [XLEN-1:0] ex_rs2_data_o,
    output logic [XLEN-1:0] ex_csr_data_o
);

    always_comb begin
        // rs1 forwarding
        if (mem_valid_i && mem_ctrl_i.reg_write && mem_ctrl_i.wb_sel != WB_MEM
            && mem_ctrl_i.rd_addr != X0 && mem_ctrl_i.rd_addr == ex_ctrl_i.rs1_addr) begin
            ex_rs1_data_o = mem_rd_data_i;
        end else if (wb_valid_i && wb_ctrl_i.reg_write && wb_ctrl_i.rd_addr != X0
                     && wb_ctrl_i.rd_addr == ex_ctrl_i.rs1_addr) begin
            ex_rs1_data_o = wb_rd_data_i;
        end else begin
            ex_rs1_data_o = ex_rs1_data_raw_i;
        end

        // rs2 forwarding
        if (mem_valid_i && mem_ctrl_i.reg_write && mem_ctrl_i.wb_sel != WB_MEM
            && mem_ctrl_i.rd_addr != X0 && mem_ctrl_i.rd_addr == ex_ctrl_i.rs2_addr) begin
            ex_rs2_data_o = mem_rd_data_i;
        end else if (wb_valid_i && wb_ctrl_i.reg_write && wb_ctrl_i.rd_addr != X0
                     && wb_ctrl_i.rd_addr == ex_ctrl_i.rs2_addr) begin
            ex_rs2_data_o = wb_rd_data_i;
        end else begin
            ex_rs2_data_o = ex_rs2_data_raw_i;
        end

        // CSR reads are interlocked until older writes commit, so they never need a value bypass.
        ex_csr_data_o = ex_csr_data_raw_i;
    end

endmodule : forwarding_unit
