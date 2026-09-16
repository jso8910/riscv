import riscv::*;

module physical_memory_checker (
    // input machine_privilege_t  current_privilege_i,
    input pmp_decoded_entry_t  pmp_decoded_i [0:PMP_ENTRY_COUNT-1],
    input mem_req_t [MEM_READ_PORTS-1:0]      mem_req_i,
    output mem_fault_t [MEM_READ_PORTS-1:0]   fault_o,
    output logic [MEM_READ_PORTS-1:0][XLEN-1:0] fault_addr_o
);
    logic [XLEN-1:0] access_addresses [0:1] [0:7];
    /* verilator lint_off ASCRANGE */
    pma_cfg_t [0:PMA_ENTRY_COUNT-1] pma_cfgs;
    /* verilator lint_on ASCRANGE */

    logic [3:0] access_width [0:1];

    // machine_privilege_t effective_privilege;
    // assign effective_privilege = machine_privilege_t'(current_privilege_i == M_MODE && mstatus_i[MSTATUS_MPRV] ? 
    //                             mstatus_i[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] :
    //                             current_privilege_i);

    // Static platform PMA map: executable main memory followed by unallocated
    // address space.
    always_comb begin
        pma_cfgs[0].addr_low = MEM_START_ADDRESS;
        pma_cfgs[0].addr_high = MEM_END_ADDRESS;
        pma_cfgs[0].main = 1'b1;
        pma_cfgs[0].writable = 1'b1;
        pma_cfgs[0].readable = 1'b1;
        pma_cfgs[0].alignment = UNALIGNED;

        pma_cfgs[1].addr_low = MEM_END_ADDRESS + 1'b1;
        pma_cfgs[1].addr_high = MTIME_ADDR - 1;
        pma_cfgs[1].main = 1'b0;
        pma_cfgs[1].writable = 1'b0;
        pma_cfgs[1].readable = 1'b0;
        pma_cfgs[1].alignment = UNALIGNED;

        pma_cfgs[2].addr_low = MTIME_ADDR;
        pma_cfgs[2].addr_high = MTIMECMP_ADDR + 7;
        pma_cfgs[2].main = 1'b0;
        pma_cfgs[2].writable = 1'b1;
        pma_cfgs[2].readable = 1'b1;
        pma_cfgs[2].alignment = DOUBLE_ALIGNED;

        pma_cfgs[3].addr_low = MTIMECMP_ADDR + 8;
        pma_cfgs[3].addr_high = {PHYS_ADDR_WIDTH{1'b1}};
        pma_cfgs[3].main = 1'b0;
        pma_cfgs[3].writable = 1'b0;
        pma_cfgs[3].readable = 1'b0;
        pma_cfgs[3].alignment = UNALIGNED;
    end

    function automatic pma_cfg_t pma_cfg_for_addr(input logic [XLEN-1:0] address);
        pma_cfg_t cfg;
        begin
            cfg = pma_cfgs[PMA_ENTRY_COUNT-1];
            for (int i = 0; i < PMA_ENTRY_COUNT; i++) begin
                if (address >= pma_cfgs[i].addr_low && address <= pma_cfgs[i].addr_high)
                    cfg = pma_cfgs[i];
            end
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

    function automatic alignment_t pma_alignment(input logic [XLEN-1:0] address);
        pma_cfg_t cfg;
        begin
            cfg = pma_cfg_for_addr(address);
            pma_alignment = cfg.alignment;
        end
    endfunction


    function automatic logic pma_main(input logic [XLEN-1:0] address);
        pma_cfg_t cfg;
        begin
            cfg = pma_cfg_for_addr(address);
            pma_main = cfg.main;
        end
    endfunction

    function automatic mem_fault_t pma_fault(input mem_op_t op);
        case (op)
            MREAD : return PMA_READ;
            MFETCH : return PMA_FETCH;
            MWRITE : return PMA_WRITE;
            default : assert (1'b0);
        endcase
    endfunction

    function automatic mem_fault_t pmp_fault(input mem_op_t op);
        case (op)
            MREAD : return PMP_READ;
            MFETCH : return PMP_FETCH;
            MWRITE : return PMP_WRITE;
            default : assert (1'b0);
        endcase
    endfunction

    genvar i;
    generate
        for (i = 0; i < MEM_READ_PORTS; i++) begin : gen_pmc
            logic [PHYS_ADDR_WIDTH:0] pmp_access_low, pmp_access_high;
            logic [PMP_ENTRY_COUNT-1:0] pmp_match_any, pmp_winner,
                                         pmp_contains_all;
            logic pmp_matched, pmp_selected_locked, pmp_selected_readable,
                  pmp_selected_writable, pmp_selected_executable,
                  pmp_selected_contains_all, bypass_permissions;
            always_comb begin
                fault_o[i] = FAULT_NONE;
                fault_addr_o[i] = mem_req_i[i].virtual_address;
                access_width[i] = '0;
                for (int j = 0; j < 8; j++)
                    access_addresses[i][j] = 0;
                pmp_access_low = '0;
                pmp_access_high = '0;
                pmp_match_any = '0;
                pmp_winner = '0;
                pmp_contains_all = '0;
                pmp_matched = 1'b0;
                pmp_selected_locked = 1'b0;
                pmp_selected_readable = 1'b0;
                pmp_selected_writable = 1'b0;
                pmp_selected_executable = 1'b0;
                pmp_selected_contains_all = 1'b0;
                bypass_permissions = 1'b0;
                if (mem_req_i[i].valid) begin
                    case (mem_req_i[i].size)
                        MEM_BYTE : begin
                            access_width[i] = 4'd1;
                            access_addresses[i][0] = mem_req_i[i].address;
                            access_addresses[i][1] = mem_req_i[i].address;
                            access_addresses[i][2] = mem_req_i[i].address;
                            access_addresses[i][3] = mem_req_i[i].address;
                            access_addresses[i][4] = mem_req_i[i].address;
                            access_addresses[i][5] = mem_req_i[i].address;
                            access_addresses[i][6] = mem_req_i[i].address;
                            access_addresses[i][7] = mem_req_i[i].address;
                        end
                        MEM_HALF : begin
                            access_width[i] = 4'd2;
                            access_addresses[i][0] = mem_req_i[i].address;
                            access_addresses[i][1] = mem_req_i[i].address + uintxlen_t'(1);
                            access_addresses[i][2] = mem_req_i[i].address;
                            access_addresses[i][3] = mem_req_i[i].address;
                            access_addresses[i][4] = mem_req_i[i].address;
                            access_addresses[i][5] = mem_req_i[i].address;
                            access_addresses[i][6] = mem_req_i[i].address;
                            access_addresses[i][7] = mem_req_i[i].address;
                        end
                        MEM_WORD : begin
                            access_width[i] = 4'd4;
                            access_addresses[i][0] = mem_req_i[i].address;
                            access_addresses[i][1] = mem_req_i[i].address + uintxlen_t'(1);
                            access_addresses[i][2] = mem_req_i[i].address + uintxlen_t'(2);
                            access_addresses[i][3] = mem_req_i[i].address + uintxlen_t'(3);
                            access_addresses[i][4] = mem_req_i[i].address;
                            access_addresses[i][5] = mem_req_i[i].address;
                            access_addresses[i][6] = mem_req_i[i].address;
                            access_addresses[i][7] = mem_req_i[i].address;
                        end
                        MEM_DOUBLE : begin
                            access_width[i] = 4'd8;
                            access_addresses[i][0] = mem_req_i[i].address;
                            access_addresses[i][1] = mem_req_i[i].address + uintxlen_t'(1);
                            access_addresses[i][2] = mem_req_i[i].address + uintxlen_t'(2);
                            access_addresses[i][3] = mem_req_i[i].address + uintxlen_t'(3);
                            access_addresses[i][4] = mem_req_i[i].address + uintxlen_t'(4);
                            access_addresses[i][5] = mem_req_i[i].address + uintxlen_t'(5);
                            access_addresses[i][6] = mem_req_i[i].address + uintxlen_t'(6);
                            access_addresses[i][7] = mem_req_i[i].address + uintxlen_t'(7);
                        end
                        MEM_NONE : begin
                            // Should not have a valid MEM_NONE access
                            assert (1'b0);
                        end
                        default: assert (1'b0);
                    endcase

                    // =========
                    // PMA logic
                    // =========
                    case (mem_req_i[i].op)
                        MFETCH : begin
                            for (int j = 0; j < 8; j++) begin
                                if (j < int'(access_width[i]) &&
                                    (!pma_readable(mem_req_i[i].address + uintxlen_t'(j)) ||
                                     !pma_main(mem_req_i[i].address + uintxlen_t'(j)))) begin
                                    // The fault should correspond with the *original* operation
                                    // (differs in the case of a translation lookaside buffer miss/page
                                    // table walk)
                                    fault_o[i] = pma_fault(mem_req_i[i].op_original);
                                end
                            end
                        end
                        MREAD : begin
                            for (int j = 0; j < 8; j++) begin
                                if (j < int'(access_width[i]) && !pma_readable(access_addresses[i][j])) begin
                                    fault_o[i] = pma_fault(mem_req_i[i].op_original);
                                end
                            end
                        end
                        MWRITE : begin
                            for (int j = 0; j < 8; j++) begin
                                if (j < int'(access_width[i]) && !pma_writable(access_addresses[i][j])) begin
                                    fault_o[i] = pma_fault(mem_req_i[i].op_original);
                                end
                            end
                        end
                        default : assert (1'b0);
                    endcase

                    case (pma_alignment(access_addresses[i][0]))
                        UNALIGNED : ;
                        // To check an access is double aligned, we have the condition that a memory read is
                        // double aligned IFF the first byte's addr[2:0] == 0. The access must also be MEM_DOUBLE
                        DOUBLE_ALIGNED : begin
                            if (access_addresses[i][0][2:0] != 3'b0 || access_width[i] != 8) begin
                                fault_o[i] = pma_fault(mem_req_i[i].op_original);
                            end
                        end
                        default : ;
                    endcase

                    // =========
                    // PMP logic
                    // =========
                    // A legal memory access spans one contiguous interval.
                    // Test overlap and containment once per PMP entry instead
                    // of independently checking every byte of the access.
                    pmp_access_low = {1'b0, mem_req_i[i].address[PHYS_ADDR_WIDTH-1:0]};
                    pmp_access_high = pmp_access_low
                                    + (PHYS_ADDR_WIDTH + 1)'(access_width[i] - 1'b1);
                    for (int j = 0; j < PMP_ENTRY_COUNT; j++) begin
                        pmp_match_any[j] = pmp_decoded_i[j].active
                                         && pmp_access_low < pmp_decoded_i[j].top
                                         && pmp_access_high >= pmp_decoded_i[j].bottom;
                        pmp_contains_all[j] = pmp_decoded_i[j].active
                                            && pmp_access_low >= pmp_decoded_i[j].bottom
                                            && pmp_access_high < pmp_decoded_i[j].top;
                        // PMP priority selects the lowest-numbered entry that
                        // overlaps any part of the access.
                        if (!pmp_matched && pmp_match_any[j]) begin
                            pmp_winner[j] = 1'b1;
                            pmp_matched = 1'b1;
                        end
                    end

                    // Fold the one-hot winner into permission and containment
                    // signals.  This avoids variable-index muxes such as
                    // pmp_cfg_i[matching_pmp_idx].
                    for (int j = 0; j < PMP_ENTRY_COUNT; j++) begin
                        if (pmp_winner[j]) begin
                            pmp_selected_locked = pmp_decoded_i[j].locked;
                            pmp_selected_readable = pmp_decoded_i[j].readable;
                            pmp_selected_writable = pmp_decoded_i[j].writable;
                            pmp_selected_executable = pmp_decoded_i[j].executable;
                            pmp_selected_contains_all = pmp_contains_all[j];
                        end
                    end

                    // M-mode bypasses permissions for an unlocked matched
                    // entry and for an unmatched access.  A partial overlap
                    // remains a fault in every privilege mode.
                    bypass_permissions = mem_req_i[i].effective_privilege == M_MODE
                                      && (!pmp_matched || !pmp_selected_locked);
                    if ((!bypass_permissions && !pmp_matched)
                        || (pmp_matched && !pmp_selected_contains_all)) begin
                        fault_o[i] = pmp_fault(mem_req_i[i].op_original);
                    end

                    if (!bypass_permissions && pmp_matched) begin
                        case (mem_req_i[i].op)
                            MFETCH : begin
                                if (!pmp_selected_executable) begin
                                    fault_o[i] = pmp_fault(mem_req_i[i].op_original);
                                end
                            end
                            MWRITE : begin
                                if (!pmp_selected_writable) begin
                                    fault_o[i] = pmp_fault(mem_req_i[i].op_original);
                                end
                            end
                            MREAD : begin
                                if (!pmp_selected_readable) begin
                                    fault_o[i] = pmp_fault(mem_req_i[i].op_original);
                                end
                            end
                            default : assert (1'b0);
                        endcase 
                    end
                end
            end
        end
        // always_comb begin
        //     pma_faulting_addr_o = '0;
        //     hardware_fault_o = '0;

        //     case (ctrl_i.mem_size)
        //         MEM_BYTE : begin
        //             access_width = 4'd1;
        //             access_addresses[0] = data_mem_addr_i;
        //             access_addresses[1] = data_mem_addr_i;
        //             access_addresses[2] = data_mem_addr_i;
        //             access_addresses[3] = data_mem_addr_i;
        //             access_addresses[4] = data_mem_addr_i;
        //             access_addresses[5] = data_mem_addr_i;
        //             access_addresses[6] = data_mem_addr_i;
        //             access_addresses[7] = data_mem_addr_i;
        //             if (!(ctrl_i.mem_read || ctrl_i.mem_write)) begin
        //                 hardware_fault_o = '1;
        //             end
        //         end
        //         MEM_HALF : begin
        //             access_width = 4'd2;
        //             access_addresses[0] = data_mem_addr_i;
        //             access_addresses[1] = data_mem_addr_i + uintxlen_t'(1);
        //             access_addresses[2] = data_mem_addr_i;
        //             access_addresses[3] = data_mem_addr_i;
        //             access_addresses[4] = data_mem_addr_i;
        //             access_addresses[5] = data_mem_addr_i;
        //             access_addresses[6] = data_mem_addr_i;
        //             access_addresses[7] = data_mem_addr_i;
        //             if (!(ctrl_i.mem_read || ctrl_i.mem_write)) begin
        //                 hardware_fault_o = '1;
        //             end
        //         end
        //         MEM_WORD : begin
        //             access_width = 4'd4;
        //             access_addresses[0] = data_mem_addr_i;
        //             access_addresses[1] = data_mem_addr_i + uintxlen_t'(1);
        //             access_addresses[2] = data_mem_addr_i + uintxlen_t'(2);
        //             access_addresses[3] = data_mem_addr_i + uintxlen_t'(3);
        //             access_addresses[4] = data_mem_addr_i;
        //             access_addresses[5] = data_mem_addr_i;
        //             access_addresses[6] = data_mem_addr_i;
        //             access_addresses[7] = data_mem_addr_i;
        //             if (!(ctrl_i.mem_read || ctrl_i.mem_write)) begin
        //                 hardware_fault_o = '1;
        //             end
        //         end
        //         MEM_DOUBLE : begin
        //             access_width = 4'd8;
        //             access_addresses[0] = data_mem_addr_i;
        //             access_addresses[1] = data_mem_addr_i + uintxlen_t'(1);
        //             access_addresses[2] = data_mem_addr_i + uintxlen_t'(2);
        //             access_addresses[3] = data_mem_addr_i + uintxlen_t'(3);
        //             access_addresses[4] = data_mem_addr_i + uintxlen_t'(4);
        //             access_addresses[5] = data_mem_addr_i + uintxlen_t'(5);
        //             access_addresses[6] = data_mem_addr_i + uintxlen_t'(6);
        //             access_addresses[7] = data_mem_addr_i + uintxlen_t'(7);
        //             if (!(ctrl_i.mem_read || ctrl_i.mem_write)) begin
        //                 hardware_fault_o = '1;
        //             end
        //         end
        //         MEM_NONE : begin
        //             access_width = 4'd0;
        //             access_addresses[0] = data_mem_addr_i;
        //             access_addresses[1] = data_mem_addr_i;
        //             access_addresses[2] = data_mem_addr_i;
        //             access_addresses[3] = data_mem_addr_i;
        //             access_addresses[4] = data_mem_addr_i;
        //             access_addresses[5] = data_mem_addr_i;
        //             access_addresses[6] = data_mem_addr_i;
        //             access_addresses[7] = data_mem_addr_i;
        //             // MEM_NONE should only be true if there isn't a memory read or memory
        //             // write
        //             if (ctrl_i.mem_read || ctrl_i.mem_write) begin
        //                 hardware_fault_o = '1;
        //             end
        //         end
        //         default: $fatal(1);
        //     endcase

        //     // =================================
        //     // Physical memory attribution logic
        //     // =================================
        //     // Note, importantly, the order of checks: read -> write -> instruction fetch
        //     // This is used because of the ordering of checks in trap_controller, where an instruction
        //     // fetch fault is raised over a write fault is raised over a read fault. The PMA checker
        //     // must check in that order so the correct address is put in pma_faulting_addr.
            
            

        //     pma_write_exception_o = '0;
        //     pma_read_exception_o = '0;
        //     if (ctrl_i.mem_read) begin
        //         // We iterate in reverse so the lowest failing byte is put in pma_faulting_addr
        //         for (int i = int'(access_width) - 1; i >= 0; i--) begin
        //             if (!pma_readable(access_addresses[i])) begin
        //                 pma_read_exception_o = '1;
        //                 pma_faulting_addr_o = access_addresses[i];
        //             end
        //         end
        //     end
        //     if (ctrl_i.mem_write) begin
        //         for (int i = int'(access_width) - 1; i >= 0; i--) begin
        //             if (!pma_writable(access_addresses[i])) begin
        //                 pma_write_exception_o = '1;
        //                 pma_faulting_addr_o = access_addresses[i];
        //             end
        //         end
        //     end

        //     case (pma_alignment(access_addresses[0]))
        //         UNALIGNED : ;
        //         // To check an access is double aligned, we have the condition that a memory read is
        //         // double aligned IFF the first byte's addr[2:0] == 0. The access must also be MEM_DOUBLE
        //         DOUBLE_ALIGNED : begin
        //             if (access_addresses[0][2:0] != 3'b0 || access_width != 8) begin
        //                 if (ctrl_i.mem_read) begin
        //                     pma_read_exception_o = '1;
        //                     pma_faulting_addr_o = access_addresses[0];
        //                 end
        //                 if (ctrl_i.mem_write) begin
        //                     pma_write_exception_o = '1;
        //                     pma_faulting_addr_o = access_addresses[0];
        //                 end
        //             end
        //         end
        //         default : ;
        //     endcase

        //     pma_instruction_fetch_exception_o = '0;
        //     for (int i = 3; i >= 0; i--) begin
        //         pma_instruction_fetch_exception_o = pma_instruction_fetch_exception_o || (!pma_readable(pc_i + uintxlen_t'(i)) || !pma_main(pc_i + uintxlen_t'(i)));
                
        //         if (!pma_readable(pc_i + uintxlen_t'(i)) || !pma_main(pc_i + uintxlen_t'(i))) begin
        //             pma_faulting_addr_o = pc_i + uintxlen_t'(i);
        //         end
        //     end

        //     // ================================
        //     // Physical memory protection logic
        //     // ================================
        //     pmp_read_exception_o = '0;
        //     pmp_write_exception_o = '0;
        //     pmp_instruction_fetch_exception_o = '0;
        //     pmp_faulting_addr_o = '0;
        //     all_access_bytes = 1;
        //     all_pc_bytes = 1;
        //     // First, we want to find the lowest PMP which matches *any* of the bytes of the memory
        //     // access. This is the priority rule outlined in Privileged Architecture 2.1.7.1.3. Priority
        //     // and Matching Logic
        //     access_matching_pmp_idx = 63;
        //     pc_matching_pmp_idx = 63;
        //     access_pmp_matched = 0;
        //     pc_pmp_matched = 0;
        //     bottom_of_range = 0;
        //     top_of_range = 0;
        //     n_trailing_1s = 0;
        //     access_pmp_range_btm = 0;
        //     access_pmp_range_top = 0;
        //     pc_pmp_range_btm = 0;
        //     pc_pmp_range_top = 0;

        //     for (int i = 63; i >= 0; i--) begin
        //         case (pmp_addr_matching_t'(pmp_cfg_i[i][PMPCFG_A_MSB : PMPCFG_A_LSB]))
        //             PMP_OFF : begin
        //                 // 0..0 doesn't match
        //                 bottom_of_range = 0;
        //                 top_of_range = 0;
        //             end
        //             PMP_TOR : begin
        //                 // The range is (pmp_addr_i[i-1] << 2)..(pmp_addr_i[i] << 2)
        //                 // if i==0, the bottom of the range is 0
        //                 if (i != 0)
        //                     bottom_of_range = {1'b0, pmp_addr_i[i-1][PMP_ADDR_WIDTH-1:0], 2'b00};
        //                 else
        //                     bottom_of_range = '0;
        //                 top_of_range = {1'b0, pmp_addr_i[i][PMP_ADDR_WIDTH-1:0], 2'b00};
                        
        //             end
        //             PMP_NA4 : begin
        //                 // range is (pmp_addr_i[i] << 2)..((pmp_addr_i[i] << 2) + 4)
        //                 bottom_of_range = {1'b0, pmp_addr_i[i][PMP_ADDR_WIDTH-1:0], 2'b00};
        //                 top_of_range = {1'b0, pmp_addr_i[i][PMP_ADDR_WIDTH-1:0], 2'b00} + (PHYS_ADDR_WIDTH + 1)'(3'd4);
        //             end
        //             PMP_NAPOT : begin
        //                 n_trailing_1s = 0;
        //                 // range is:
        //                 // base_addr = (pmp_addr_i[i] >> (n_trailing_1s + 1)) << (n_trailing_1s + 3)
        //                 // This clears n_trailing_1s bits, then, on net, shifts the address by 2
        //                 // size = 1 << (3 + n_trailing_1s)
        //                 // so the range is base_addr..base_addr+size (uninclusive)
        //                 for (int j = 0; j < PMP_ADDR_WIDTH - 1; j++) begin
        //                     // The moment this if statement isn't taken, n_trailing_1s == j will never
        //                     // be true again, and thus it will never be incremented again.
        //                     if (pmp_addr_i[i][j] == 1'b1) begin
        //                         if (n_trailing_1s == j[5:0]) begin
        //                             n_trailing_1s += 1;
        //                         end
        //                     end
        //                 end
        //                 // Widen before shifting: a NAPOT region can end at the
        //                 // exclusive end of the physical address space.
        //                 bottom_of_range = ({3'b000, pmp_addr_i[i][PMP_ADDR_WIDTH-1:0]} >> (n_trailing_1s + 1))
        //                                 << (n_trailing_1s + 3);
        //                 top_of_range = bottom_of_range
        //                             + ((PHYS_ADDR_WIDTH + 1)'(1'b1) << (3 + n_trailing_1s));
        //             end
        //             // Here, I skip the $fatal(1) because I specifically know that there will never be
        //             // any more PMA modes.
        //             // This is necessary because, for a very brief moment at the time when reset is
        //             // asserted, this config value == 2'bxx (since the non blocking cfg <= 0 in the CSR
        //             // hasn't yet completed). So, this default branch is accessed briefly.
        //             default: ;
        //         endcase
        //         for (int j = 0; j < 8; j++) begin
        //             if (j < int'(access_width)) begin
        //                 if (bottom_of_range <= {1'b0, access_addresses[j][PHYS_ADDR_WIDTH-1:0]} && {1'b0, access_addresses[j][PHYS_ADDR_WIDTH-1:0]} < top_of_range) begin
        //                     access_matching_pmp_idx = i[5:0];
        //                     access_pmp_matched = 1;
        //                     access_pmp_range_btm = bottom_of_range;
        //                     access_pmp_range_top = top_of_range;
        //                 end
        //             end
        //             // PC is only a 4 byte access
        //             if (j < 4) begin
        //                 if (bottom_of_range <= ({1'b0, pc_i[PHYS_ADDR_WIDTH-1:0]} + (PHYS_ADDR_WIDTH + 1)'(unsigned'(j))) && ({1'b0, pc_i[PHYS_ADDR_WIDTH-1:0]} + (PHYS_ADDR_WIDTH + 1)'(unsigned'(j))) < top_of_range) begin
        //                     pc_matching_pmp_idx = i[5:0];
        //                     pc_pmp_matched = 1;
        //                     pc_pmp_range_btm = bottom_of_range;
        //                     pc_pmp_range_top = top_of_range;
        //                 end
        //             end
        //         end
        //     end


        //     // Now, we check to see if the memory accesses fail their PMPs. We do the memory access
        //     // before the PC instruction fetch because of the same reason as above (in the PMA).


        //     // If we are currently in M mode, we only apply a PMP's permissions if L == 1. However,
        //     // there is still a fault if the PMP partially covers the memory area.
        //     // We also bypass the permissions if there was no match, because M-mode permits unmatched accesses.
        //     bypass_permissions = effective_privilege == M_MODE && (!access_pmp_matched || !pmp_cfg_i[access_matching_pmp_idx][PMPCFG_L_IDX]);
        //     // There are three conditions for a PMP fault:
        //     //  1. There is at least one implemented PMP, but not one covering the entirety of this
        //     //     access.
        //     //  2. Not all bytes are in the selected PMP region (because the prioritization selects the
        //     //     lowest PMP which matches *any* of the bytes of the access)
        //     //  3. The R/W bit corresponding with this access's operation is not set.
        //     for (int i = 0; i < int'(access_width); i++) begin
        //         // this works even if no pmp matched because the default (0..0) has no address matches
        //         // even in any edge case
        //         if (!(access_pmp_range_btm <= {1'b0, access_addresses[i][PHYS_ADDR_WIDTH-1:0]} && {1'b0, access_addresses[i][PHYS_ADDR_WIDTH-1:0]} < access_pmp_range_top)) begin
        //             all_access_bytes = 0;
        //         end
        //     end
        //     if ((!bypass_permissions && PMP_ENTRY_COUNT != 0 && !access_pmp_matched) ||
        //         (!bypass_permissions && access_pmp_matched && ctrl_i.mem_read && !pmp_cfg_i[access_matching_pmp_idx][PMPCFG_R_IDX]) ||
        //         (!bypass_permissions && access_pmp_matched && ctrl_i.mem_write && !pmp_cfg_i[access_matching_pmp_idx][PMPCFG_W_IDX]) ||
        //         (access_pmp_matched && !all_access_bytes)) begin
        //         if (ctrl_i.mem_read) begin
        //             pmp_read_exception_o = '1;
        //             pmp_faulting_addr_o = data_mem_addr_i;
        //         end else if (ctrl_i.mem_write) begin
        //             pmp_write_exception_o = '1;
        //             pmp_faulting_addr_o = data_mem_addr_i;
        //         end
        //     end 

        //     // Instruction fetches always use the current privilege rather than the effective (MPRV) privilege.
        //     bypass_permissions = current_privilege_i == M_MODE && (!pc_pmp_matched || !pmp_cfg_i[pc_matching_pmp_idx][PMPCFG_L_IDX]);
        //     for (int i = 0; i < 4; i++) begin
        //         // this works even if no pmp matched because the default (0..0) has no address matches
        //         // even in any edge case
        //         if (!(pc_pmp_range_btm <= ({1'b0, pc_i[PHYS_ADDR_WIDTH-1:0]} + (PHYS_ADDR_WIDTH + 1)'(unsigned'(i))) && ({1'b0, pc_i[PHYS_ADDR_WIDTH-1:0]} + (PHYS_ADDR_WIDTH + 1)'(unsigned'(i))) < pc_pmp_range_top)) begin
        //             all_pc_bytes = 0;
        //         end
        //     end
        //     // Now, the same checks on the PC, but we need to check executability (read not required).
        //     if ((!bypass_permissions && PMP_ENTRY_COUNT != 0 && !pc_pmp_matched) ||
        //         (!bypass_permissions && pc_pmp_matched && !pmp_cfg_i[pc_matching_pmp_idx][PMPCFG_X_IDX]) ||
        //         (pc_pmp_matched && !all_pc_bytes)) begin
        //         pmp_instruction_fetch_exception_o = '1;
        //         pmp_faulting_addr_o = pc_i;
        //     end
        // end
    endgenerate
endmodule : physical_memory_checker
