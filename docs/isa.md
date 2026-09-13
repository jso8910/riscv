# RISC-V Core ISA

- RV64I, version 2.1
- `IALIGN=32`
- Little-endian
- Full PMA and PMP support with 64 PMP entries and faults on illegal accesses.
- Sv39 virtual memory support with separate TLBs for instruction and data accesses.
- Support for M, S, and U privilege modes.
- Interrupts: support for timer interrupts and software interrupts. Supervisor external interrupts
  will trap, but there isn't an explicit input port to the core for external interrupts (hence why
  machine external interrupts aren't accessible).

Implemented extensions:
- Zicsr
- Zicntr — cycle, time, and instret counters implemented.
- Zihpm - counters 3-31 read-only zero.
- Sstc
- Sv39
- Svade — when A/D bits need updating, page fault is raised
- Svbare
