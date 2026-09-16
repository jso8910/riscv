- Pipeline flush on store if the store address matches an in flight instruction
- Making sure memory write is conditional on no fault in the instruction (eg an instruction fetch
  page fault is the case I'm thinking of).
- Figure out more realistic memory interface (latency, multiple requests at once (from cache to memory), AXI (??), cache, etc.)