// Implementation of a pass-through skid buffer for AXI.
//
// The purpose of this buffer is to break the combinational READY path from the downstream
// interface to the upstream interface by delaying backpressure by one cycle.
//
// Without the skid buffer, when ready_i is deasserted by the downstream, that signal may need to
// propagate through upstream logic in the same cycle so that the upstream can stop advancing its
// data. This can create a long timing path.
//
// With the skid buffer, any valid item that was already in flight when ready_i is deasserted is
// captured in the buffer. On the following cycle, ready_o is deasserted based only on the
// registered buffer state, allowing the upstream to stall without a combinational dependency on
// ready_i.

`ifdef FORMAL
`include "rtl/misc/formal_temporal.svh"
`endif

module skid_buffer #(
    type T = logic [7:0],
    T RST_VAL = '0
) (
    input logic  clk,
    input logic  rst_n,

    // Upstream (data source)
    input logic  valid_i,
    output logic ready_o,
    input T      data_i,

    // Downstream (data receiver)
    output logic valid_o,
    input logic  ready_i,
    output T     data_o
);
    T buffer;
    logic buffer_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buffer <= RST_VAL;
            buffer_valid <= '0;
        end
        // If data from the master is valid, and the slave isn't ready, hold it constant
        // by putting it into the buffer (if empty — otherwise, we stall the upstream)
        else if (valid_i && !ready_i && !buffer_valid) begin
            buffer <= data_i;
            buffer_valid <= '1;
        end
        // If the the slave is ready for new data (ie it is ready to consume the data on this clock
        // edge), then we should invalidate the buffer and thus allow the upstream data to begin
        // passing through directly to the downstream.
        else if (ready_i) begin
            buffer_valid <= '0;
        end
    end

    always_comb begin
        // If we have valid data in the buffer, we want to 
        if (buffer_valid) begin
            data_o = buffer;
            valid_o = buffer_valid;
        end else begin
            data_o = data_i;
            valid_o = valid_i;
        end

        // We also need to send the signal to the master of if we're ready to receive more data.
        // We want to receive more data if the slave is ready for more data or the buffer isn't
        // full.
        //  1. An empty buffer can accept an item even if downstream is stalled
        //  2. While technically a full buffer could accept an item if ready_i is asserted, we don't
        //     want to do this — the whole point of the skid buffer is to break the timing path
        //     between ready_i and ready_o. Instead, we allow the buffer to empty.
        ready_o = !buffer_valid;
    end

    `ifdef FORMAL
    // The original properties below used concurrent SVA.  Slang/Yosys cannot
    // lower that syntax, so the temporal helper macros express each one-cycle
    // implication with $past() and a post-reset history-valid flag instead.
    `FORMAL_DECLARE_PAST_VALID(f_past_valid, clk, rst_n)
    `FORMAL_DECLARE_HISTORY_VALID(f_history_valid, clk)

    // AXI source rule: after observing VALID while the skid buffer is not
    // ready, the source must keep both VALID and DATA unchanged next cycle.
    `ifdef SKID_BUFFER_STANDALONE
        // Slang/Yosys does not lower $initstate.  An initialized formal-only
        // flag is equivalent here: it is one only at the first sampled clock,
        // where it constrains the standalone environment to hold reset active.
        logic formal_first_cycle = 1'b1;
        always_ff @(posedge clk) begin
            if (formal_first_cycle)
                assume(!rst_n);
            formal_first_cycle <= 1'b0;
        end
        `FORMAL_ASSUME_NEXT_WHILE(clk, f_past_valid, rst_n,
            valid_i && !ready_o,
            valid_i && data_i == $past(data_i))
    `else
        `FORMAL_ASSERT_NEXT_WHILE(clk, f_past_valid, rst_n,
            valid_i && !ready_o,
            valid_i && data_i == $past(data_i))
    `endif

    // AXI receiver rule: a stalled output beat must remain valid and keep its
    // payload until the downstream receiver accepts it.
    `FORMAL_ASSERT_NEXT_WHILE(clk, f_past_valid, rst_n,
        valid_o && !ready_i,
        valid_o && data_o == $past(data_o))

    // If there isn't data in the buffer and the downstream isn't ready, the buffer should be
    // filled with valid data (if applicable), the upstream should not be allowed to continue
    // sending data.
    `FORMAL_ASSERT_NEXT_WHILE(clk, f_past_valid, rst_n,
        !buffer_valid && valid_i && !ready_i,
        buffer_valid
            && !ready_o
            && buffer == $past(data_i)
            && data_o == $past(data_i)
            && valid_o)

    // If there is data in the buffer, and the downstream is ready, the buffer should be emptied,
    // and data_o should equal data_i on the next clock cycle (regardless of valid_i). The upstream
    // should also be told the downstream is ready for more data.
    `FORMAL_ASSERT_NEXT_WHILE(clk, f_past_valid, rst_n,
        buffer_valid && ready_i,
        !buffer_valid && ready_o && data_o == data_i && valid_o == valid_i)

    // If there is already data in the buffer and the downstream isn't ready, we want to stall the
    // upstream, as well as keeping the data to the downstream stable
    `FORMAL_ASSERT_NEXT_WHILE(clk, f_past_valid, rst_n,
        buffer_valid && !ready_i,
        buffer_valid && !ready_o && data_o == $past(data_o) && valid_o)

    `FORMAL_ASSERT_NEXT_WHILE(clk, f_past_valid, rst_n,
        !buffer_valid && ready_i,
        !buffer_valid && ready_o && data_o == data_i && valid_o == valid_i)

    // Same-cycle mux properties: a full buffer must drive its saved beat;
    // an empty buffer must be transparent and ready to accept one beat.
    always_comb begin
        if (rst_n && buffer_valid)
            assert (valid_o && data_o == buffer);
        if (rst_n && !buffer_valid)
            assert (ready_o && valid_o == valid_i && data_o == data_i);
    end

    // The environment obeys the AXI reset requirement, and reset clears the
    // buffer.  These intentionally use the non-reset history flag because
    // their antecedent is the reset cycle itself.
    always_ff @(posedge clk) begin
        if (f_history_valid && $past(!rst_n)) begin
            assume (!valid_i);
            assert (!buffer_valid);
        end
    end

    // Immediate cover monitor for the original four-cycle sequence:
    // capture while stalled, observe the full buffer, make the downstream
    // ready, then observe that the buffer drains.
    logic [2:0] f_cover_phase;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            f_cover_phase <= '0;
        end else begin
            case (f_cover_phase)
                3'd0: f_cover_phase <= (!buffer_valid && valid_i && !ready_i) ? 3'd1 : 3'd0;
                3'd1: f_cover_phase <= buffer_valid ? 3'd2 : 3'd0;
                3'd2: f_cover_phase <= ready_i ? 3'd3 : 3'd0;
                default: begin
                    cover (!buffer_valid);
                    f_cover_phase <= '0;
                end
            endcase
        end
    end
    `endif
endmodule : skid_buffer
