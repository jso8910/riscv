/* Adapted from Embench's riscv32/rv32wallyverilog linker-script template.
 * The target has a flat 2 MiB RAM from zero and reserves the final 80 bytes
 * for the simulator benchmark mailbox and tohost word. */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    RAM  (rwx) : ORIGIN = 0x00000000, LENGTH = 0x001fffb0
    HOST (rw)  : ORIGIN = 0x001fffb0, LENGTH = 0x00000050
}

SECTIONS {
    . = ORIGIN(RAM);
    .text : {
        KEEP(*(.text.start))
        *(.text .text.*)
    } > RAM
    .rodata : { *(.rodata .rodata.*) } > RAM
    .sdata : { *(.sdata .sdata.* .srodata .srodata.*) } > RAM
    .data : { *(.data .data.*) } > RAM

    . = ALIGN(8);
    __bss_start = .;
    .bss (NOLOAD) : { *(.sbss .sbss.* .bss .bss.* COMMON) } > RAM
    . = ALIGN(8);
    __bss_end = .;
    .stack (NOLOAD) : {
        . = ALIGN(16);
        . += 0x4000;
        __stack_top = .;
    } > RAM
    ASSERT(__stack_top <= ORIGIN(RAM) + LENGTH(RAM), "benchmark image exceeds RAM")

    .bench_mailbox ORIGIN(HOST) (NOLOAD) : { . += 0x40; } > HOST
    .tohost 0x001ffff0 (NOLOAD) : { . += 8; } > HOST

    PROVIDE(__global_pointer$ = 0);
    /DISCARD/ : { *(.comment .note* .eh_frame* .gnu*) }
}
