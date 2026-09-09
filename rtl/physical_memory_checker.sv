import riscv::*;

module physical_memory_checker (
    input machine_privilege_t  current_privilege_i,
    input logic [7:0]          pmp_cfg_i [0:63],
    input logic [XLEN-1:0]     pmp_addr_i [0:63],
    input logic [XLEN-1:0]     pc_i,
    input ctrl_t               ctrl_i,
    input logic [XLEN-1:0]     data_mem_addr_i,
    input logic [XLEN-1:0]     mstatus_i,
    output logic               pma_instruction_fetch_exception_o,
    output logic               pma_write_exception_o,
    output logic               pma_read_exception_o,
    output logic               hardware_fault_o,
    output logic [XLEN-1:0]    pma_faulting_addr_o,
    output logic               pmp_write_exception_o,
    output logic               pmp_read_exception_o,
    output logic               pmp_instruction_fetch_exception_o,
    output logic [XLEN-1:0]    pmp_faulting_addr_o
);
    logic access_empty;
    logic [XLEN-1:0] access_addresses [0:3];
    pma_cfg_t [0:2] pma_cfgs;

    logic access_pmp_matched, pc_pmp_matched, all_access_bytes, all_pc_bytes,
          bypass_permissions;
    logic [XLEN+2:0] bottom_of_range, top_of_range, access_pmp_range_btm, access_pmp_range_top,
                     pc_pmp_range_btm, pc_pmp_range_top;
    logic [5:0] access_matching_pmp_idx, pc_matching_pmp_idx, n_trailing_1s;

    machine_privilege_t effective_privilege;
    assign effective_privilege = machine_privilege_t'(current_privilege_i == M_MODE && mstatus_i[MSTATUS_MPRV] ? 
                                mstatus_i[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] :
                                current_privilege_i);

    // Static platform PMA map: executable main memory followed by unallocated
    // address space.
    always_comb begin
        pma_cfgs[0].addr_low = MEM_START_ADDRESS;
        pma_cfgs[0].addr_high = MEM_END_ADDRESS;
        pma_cfgs[0].main = 1'b1;
        pma_cfgs[0].writable = 1'b1;
        pma_cfgs[0].readable = 1'b1;

        pma_cfgs[1].addr_low = MEM_END_ADDRESS + 1'b1;
        pma_cfgs[1].addr_high = {XLEN{1'b1}};
        pma_cfgs[1].main = 1'b0;
        pma_cfgs[1].writable = 1'b0;
        pma_cfgs[1].readable = 1'b0;
    end

    function automatic pma_cfg_t pma_cfg_for_addr(input logic [XLEN-1:0] address);
        pma_cfg_t cfg;
        begin
            cfg = pma_cfgs[2];
            if (address >= pma_cfgs[0].addr_low && address <= pma_cfgs[0].addr_high)
                cfg = pma_cfgs[0];
            else if (address >= pma_cfgs[1].addr_low && address <= pma_cfgs[1].addr_high)
                cfg = pma_cfgs[1];
            pma_cfg_for_addr = cfg;
        end
    endfunction

    function automatic logic pma_readable(input logic [XLEN-1:0] address);
        pma_cfg_t cfg;
        begin
            cfg = pma_cfg_for_addr(address);
            pma_readable = cfg.readable;
        end
    endfunction

    function automatic logic pma_writable(input logic [XLEN-1:0] address);
        pma_cfg_t cfg;
        begin
            cfg = pma_cfg_for_addr(address);
            pma_writable = cfg.writable;
        end
    endfunction

    function automatic logic pma_main(input logic [XLEN-1:0] address);
        pma_cfg_t cfg;
        begin
            cfg = pma_cfg_for_addr(address);
            pma_main = cfg.main;
        end
    endfunction

    always_comb begin
        pma_faulting_addr_o = '0;
        hardware_fault_o = '0;

        access_empty = '0;
        case (ctrl_i.mem_size)
            MEM_BYTE : begin
                access_addresses[0] = data_mem_addr_i;
                access_addresses[1] = data_mem_addr_i;
                access_addresses[2] = data_mem_addr_i;
                access_addresses[3] = data_mem_addr_i;
            end
            MEM_HALF : begin
                access_addresses[0] = data_mem_addr_i;
                access_addresses[1] = data_mem_addr_i + 1'b1;
                access_addresses[2] = data_mem_addr_i;
                access_addresses[3] = data_mem_addr_i;
            end
            MEM_WORD : begin
                access_addresses[0] = data_mem_addr_i;
                access_addresses[1] = data_mem_addr_i + 1'd1;
                access_addresses[2] = data_mem_addr_i + 2'd2;
                access_addresses[3] = data_mem_addr_i + 2'd3;
            end
            MEM_NONE : begin
                access_addresses[0] = data_mem_addr_i;
                access_addresses[1] = data_mem_addr_i;
                access_addresses[2] = data_mem_addr_i;
                access_addresses[3] = data_mem_addr_i;
                access_empty = '1;
            end
            default: $fatal(1);
        endcase

        // =================================
        // Physical memory attribution logic
        // =================================
        // Note, importantly, the order of checks: read -> write -> instruction fetch
        // This is used because of the ordering of checks in trap_controller, where an instruction
        // fetch fault is raised over a write fault is raised over a read fault. The PMA checker
        // must check in that order so the correct address is put in pma_faulting_addr.
        // access_empty (ie MEM_NONE) should only be true if there isn't a memory read or memory
        // write
        if (access_empty != ~(ctrl_i.mem_read || ctrl_i.mem_write)) begin
            hardware_fault_o = '1;
        end

        pma_write_exception_o = '0;
        pma_read_exception_o = '0;
        if (!access_empty) begin
            if (ctrl_i.mem_read) begin
                // We iterate in reverse so the lowest failing byte is put in pma_faulting_addr
                for (int i = 3; i >= 0; i--) begin
                    if (!pma_readable(access_addresses[i])) begin
                        pma_read_exception_o = '1;
                        pma_faulting_addr_o = access_addresses[i];
                    end
                end
            end
            if (ctrl_i.mem_write) begin
                for (int i = 3; i >= 0; i--) begin
                    if (!pma_writable(access_addresses[i])) begin
                        pma_write_exception_o = '1;
                        pma_faulting_addr_o = access_addresses[i];
                    end
                end
            end
        end

        pma_instruction_fetch_exception_o = '0;
        for (int i = 3; i >= 0; i--) begin
            pma_instruction_fetch_exception_o = pma_instruction_fetch_exception_o || (!pma_readable(pc_i + i) || !pma_main(pc_i + i));
            if (!pma_readable(pc_i + i) || !pma_main(pc_i + i)) begin
                pma_faulting_addr_o = pc_i + i;
            end
        end

        // ================================
        // Physical memory protection logic
        // ================================
        pmp_read_exception_o = '0;
        pmp_write_exception_o = '0;
        pmp_instruction_fetch_exception_o = '0;
        pmp_faulting_addr_o = '0;
        all_access_bytes = 1;
        all_pc_bytes = 1;
        // First, we want to find the lowest PMP which matches *any* of the bytes of the memory
        // access. This is the priority rule outlined in Privileged Architecture 2.1.7.1.3. Priority
        // and Matching Logic
        access_matching_pmp_idx = 63;
        pc_matching_pmp_idx = 63;
        access_pmp_matched = 0;
        pc_pmp_matched = 0;
        bottom_of_range = 0;
        top_of_range = 0;
        n_trailing_1s = 0;
        access_pmp_range_btm = 0;
        access_pmp_range_top = 0;
        pc_pmp_range_btm = 0;
        pc_pmp_range_top = 0;

        for (int i = 63; i >= 0; i--) begin
            case (pmp_cfg_i[i][PMPCFG_A_MSB : PMPCFG_A_LSB])
                PMP_OFF : begin
                    // 0..0 doesn't match
                    bottom_of_range = 0;
                    top_of_range = 0;
                end
                PMP_TOR : begin
                    // The range is (pmp_addr_i[i-1] << 2)..(pmp_addr_i[i] << 2)
                    // if i==0, the bottom of the range is 0
                    if (i != 0)
                        bottom_of_range = {1'b0, pmp_addr_i[i-1], 2'b00};
                    else
                        bottom_of_range = '0;
                    top_of_range = {1'b0, pmp_addr_i[i], 2'b00};
                    
                end
                PMP_NA4 : begin
                    // range is (pmp_addr_i[i] << 2)..((pmp_addr_i[i] << 2) + 4)
                    bottom_of_range = {1'b0, pmp_addr_i[i], 2'b00};
                    top_of_range = {1'b0, pmp_addr_i[i], 2'b00} + 4;
                end
                PMP_NAPOT : begin
                    n_trailing_1s = 0;
                    // range is:
                    // base_addr = (pmp_addr_i[i] >> (n_trailing_1s + 1)) << (n_trailing_1s + 3)
                    // This clears n_trailing_1s bits, then, on net, shifts the address by 2
                    // size = 1 << (3 + n_trailing_1s)
                    // so the range is base_addr..base_addr+size (uninclusive)
                    for (int j = 0; j < 32; j++) begin
                        // The moment this if statement isn't taken, n_trailing_1s == j will never
                        // be true again, and thus it will never be incremented again.
                        if (pmp_addr_i[i][j] == 1'b1) begin
                            if (n_trailing_1s == j) begin
                                n_trailing_1s += 1;
                            end
                        end
                    end
                    // Widen before shifting: a NAPOT region can end above the
                    // 32-bit address space, even though individual accesses are
                    // XLEN wide.
                    bottom_of_range = ({3'b000, pmp_addr_i[i]} >> (n_trailing_1s + 1))
                                      << (n_trailing_1s + 3);
                    top_of_range = bottom_of_range
                                 + ((XLEN + 3)'(1) << (3 + n_trailing_1s));
                end
                // Here, I skip the $fatal(1) because I specifically know that there will never be
                // any more PMA modes.
                // This is necessary because, for a very brief moment at the time when reset is
                // asserted, this config value == 2'bxx (since the non blocking cfg <= 0 in the CSR
                // hasn't yet completed). So, this default branch is accessed briefly.
                default: ;
            endcase
            for (int j = 0; j < 4; j++) begin
                if (bottom_of_range <= access_addresses[j] && access_addresses[j] < top_of_range) begin
                    access_matching_pmp_idx = i;
                    access_pmp_matched = 1;
                    access_pmp_range_btm = bottom_of_range;
                    access_pmp_range_top = top_of_range;
                end
                if (bottom_of_range <= pc_i + j && pc_i + j < top_of_range) begin
                    pc_matching_pmp_idx = i;
                    pc_pmp_matched = 1;
                    pc_pmp_range_btm = bottom_of_range;
                    pc_pmp_range_top = top_of_range;
                end
            end
        end


        // Now, we check to see if the memory accesses fail their PMPs. We do the memory access
        // before the PC instruction fetch because of the same reason as above (in the PMA).


        // If we are currently in M mode, we only apply a PMP's permissions if L == 1. However,
        // there is still a fault if the PMP partially covers the memory area.
        // We also bypass the permissions if there was no match, because M-mode permits unmatched accesses.
        bypass_permissions = effective_privilege == M_MODE && (!access_pmp_matched || !pmp_cfg_i[access_matching_pmp_idx][PMPCFG_L_IDX]);
        // There are three conditions for a PMP fault:
        //  1. There is at least one implemented PMP, but not one covering the entirety of this
        //     access.
        //  2. Not all bytes are in the selected PMP region (because the prioritization selects the
        //     lowest PMP which matches *any* of the bytes of the access)
        //  3. The R/W bit corresponding with this access's operation is not set.
        for (int i = 0; i < 4; i++) begin
            // this works even if no pmp matched because the default (0..0) has no address matches
            // even in any edge case
            if (!(access_pmp_range_btm <= access_addresses[i] && access_addresses[i] < access_pmp_range_top)) begin
                all_access_bytes = 0;
            end
        end
        if ((!bypass_permissions && PMP_ENTRY_COUNT != 0 && !access_pmp_matched) ||
            (!bypass_permissions && access_pmp_matched && ctrl_i.mem_read && !pmp_cfg_i[access_matching_pmp_idx][PMPCFG_R_IDX]) ||
            (!bypass_permissions && access_pmp_matched && ctrl_i.mem_write && !pmp_cfg_i[access_matching_pmp_idx][PMPCFG_W_IDX]) ||
            (access_pmp_matched && !all_access_bytes)) begin
            if (ctrl_i.mem_read) begin
                pmp_read_exception_o = '1;
                pmp_faulting_addr_o = data_mem_addr_i;
            end else if (ctrl_i.mem_write) begin
                pmp_write_exception_o = '1;
                pmp_faulting_addr_o = data_mem_addr_i;
            end
        end

        // Instruction fetches always use the current privilege rather than the effective (MPRV) privilege.
        bypass_permissions = current_privilege_i == M_MODE && (!pc_pmp_matched || !pmp_cfg_i[pc_matching_pmp_idx][PMPCFG_L_IDX]);
        for (int i = 0; i < 4; i++) begin
            // this works even if no pmp matched because the default (0..0) has no address matches
            // even in any edge case
            if (!(pc_pmp_range_btm <= pc_i + i && pc_i + i < pc_pmp_range_top)) begin
                all_pc_bytes = 0;
            end
        end
        // Now, the same checks on the PC, but we need to check executability (read not required).
        if ((!bypass_permissions && PMP_ENTRY_COUNT != 0 && !pc_pmp_matched) ||
            (!bypass_permissions && pc_pmp_matched && !pmp_cfg_i[pc_matching_pmp_idx][PMPCFG_X_IDX]) ||
            (pc_pmp_matched && !all_pc_bytes)) begin
            pmp_instruction_fetch_exception_o = '1;
            pmp_faulting_addr_o = pc_i;
        end
    end
endmodule : physical_memory_checker
