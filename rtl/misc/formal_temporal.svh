`ifndef RISCV_FORMAL_TEMPORAL_SVH
`define RISCV_FORMAL_TEMPORAL_SVH

// Declare a one-bit history-valid flag for immediate formal assertions that
// use $past(...).  The flag is clear during reset and becomes true one clock
// after reset is released, so a one-cycle assertion never reads a pre-reset or
// uninitialized $past value.
//
// Example:
//   `FORMAL_DECLARE_PAST_VALID(f_past_valid, clk, rst_n)
//
`define FORMAL_DECLARE_PAST_VALID(NAME, CLK, RST_N) \
    logic NAME = 1'b0; \
    always_ff @(posedge CLK or negedge RST_N) begin \
        if (!(RST_N)) \
            NAME <= 1'b0; \
        else \
            NAME <= 1'b1; \
    end

// Declare a history-valid flag that becomes true after the first sampled
// clock and is not reset.  Use this only for properties that intentionally
// inspect a reset cycle itself, such as "reset implies empty next cycle".
`define FORMAL_DECLARE_HISTORY_VALID(NAME, CLK) \
    logic NAME = 1'b0; \
    always_ff @(posedge CLK) begin \
        NAME <= 1'b1; \
    end

// Assert a one-clock non-overlapped implication using immediate assertions:
//
//     INITIAL_CONDITION |=> NEXT_CONDITION
//
// The macro evaluates INITIAL_CONDITION in the preceding sampled cycle with
// $past(), then evaluates NEXT_CONDITION in the current sampled cycle.  The
// HISTORY_VALID flag, created by FORMAL_DECLARE_PAST_VALID, proves that a
// previous post-reset clock exists before $past() is relied upon.
//
// To model "disable iff (!rst_n)", include rst_n in both conditions, e.g.:
//   `FORMAL_ASSERT_NEXT(clk, f_past_valid,
//       rst_n && request,
//       rst_n && response)
//
`define FORMAL_ASSERT_NEXT(CLK, HISTORY_VALID, INITIAL_CONDITION, NEXT_CONDITION) \
    always_ff @(posedge CLK) begin \
        if ((HISTORY_VALID) && $past(INITIAL_CONDITION)) \
            assert (NEXT_CONDITION); \
    end

// Reset/enable-aware form of FORMAL_ASSERT_NEXT.  ENABLE must hold in both
// sampled cycles before the implication is checked.  Passing rst_n as ENABLE
// gives the same reset behavior as "disable iff (!rst_n)" for a one-cycle
// property: reset cancels an in-flight antecedent instead of requiring a
// consequent while reset is active.
`define FORMAL_ASSERT_NEXT_WHILE(CLK, HISTORY_VALID, ENABLE, INITIAL_CONDITION, NEXT_CONDITION) \
    always_ff @(posedge CLK) begin \
        if ((HISTORY_VALID) && (ENABLE) && $past(ENABLE) && $past(INITIAL_CONDITION)) \
            assert (NEXT_CONDITION); \
    end

// Assumption counterpart for a one-cycle implication.  This is used for
// protocol obligations of the formal environment, such as an AXI source
// keeping VALID and DATA stable while it is backpressured.
`define FORMAL_ASSUME_NEXT_WHILE(CLK, HISTORY_VALID, ENABLE, INITIAL_CONDITION, NEXT_CONDITION) \
    always_ff @(posedge CLK) begin \
        if ((HISTORY_VALID) && (ENABLE) && $past(ENABLE) && $past(INITIAL_CONDITION)) \
            assume (NEXT_CONDITION); \
    end

`endif
