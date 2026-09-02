OUTPUT_ARCH("riscv")
ENTRY(rvtest_entry_point)

/*
 * ============================================================
 * Memory map
 * ============================================================
 *
 * IMEM:
 *   0x00000000 - 0x000fffff
 *
 * DMEM:
 *   0x00100000 - 0x001fffff
 */

IMEM_ORIGIN = 0x00000000;
IMEM_LENGTH = 0x00100000;

DMEM_ORIGIN = 0x00100000;
DMEM_LENGTH = 0x00100000;

TEST_BASE = IMEM_ORIGIN;

NUM_HARTS = 1;

/*
 * ACT's normal default is 128 KiB.
 * You have 1 MiB of DMEM, so that's fine.
 */
STACK_SIZE = 0x00020000;

/*
 * Reserve the final 16 bytes of DMEM:
 *
 * 0x001ffff0 - 0x001ffff7 : tohost
 * 0x001ffff8 - 0x001fffff : fromhost
 */
TOHOST_ADDRESS = 0x001ffff0;


MEMORY
{
    imem (rx) : ORIGIN = IMEM_ORIGIN, LENGTH = IMEM_LENGTH
    dmem (rw) : ORIGIN = DMEM_ORIGIN, LENGTH = DMEM_LENGTH
}


PROVIDE(__stack_size = STACK_SIZE);
PROVIDE(__num_harts = NUM_HARTS);


SECTIONS
{
    /*
     * ========================================================
     * Instruction memory
     * ========================================================
     */

    .text.init TEST_BASE :
    {
        *(.text.init)
    } > imem


    .text.rvtest . :
    {
        *(.text.rvtest)
        *(.text.rvtest.*)
    } > imem


    /*
     * Remember where ACT's test code ended.
     *
     * We need this because ACT requires .text.rvmodel to appear
     * later in the linker script, after the data sections.
     */
    __rvtest_text_end = .;



    /*
     * ========================================================
     * Data memory
     * ========================================================
     */

    .rodata DMEM_ORIGIN :
    {
        *(.rodata)
        *(.rodata.*)

        *(.srodata)
        *(.srodata.*)
    } > dmem


    .data . :
    {
        *(.data)
        *(.data.*)

        *(.sdata)
        *(.sdata.*)
    } > dmem


    . = ALIGN(16);

    .bss . :
    {
        __bss_start = .;

        *(.sbss)
        *(.sbss.*)

        *(.bss)
        *(.bss.*)

        *(COMMON)

        . = ALIGN(16);

        __bss_end = .;
    } > dmem


    /*
     * Stack comes immediately after normal test data.
     */
    . = ALIGN(16);

    __stack_bottom = .;

    . += __stack_size * __num_harts;

    __stack_top = .;


    /*
     * Don't allow test data/stack to collide with tohost.
     */
    ASSERT(
        __stack_top <= TOHOST_ADDRESS,
        "ACT data/stack exceeds DMEM"
    )


    /*
     * Place tohost/fromhost at the very top of DMEM.
     */
    .tohost TOHOST_ADDRESS :
    {
        KEEP(*(.tohost))
    } > dmem



    /*
     * ========================================================
     * Remaining executable code
     * ========================================================
     *
     * ACT requires .text.rvmodel to OCCUR AFTER the data
     * sections in this linker script.
     *
     * But we explicitly give it an address back inside IMEM.
     */

    __rvmodel_start = ALIGN(__rvtest_text_end, 16);

    .text.rvmodel __rvmodel_start :
    {
        *(.text.rvmodel)
        *(.text.rvmodel.*)

        /*
         * Catch any remaining text sections.
         */
        *(.text)
        *(.text.*)
    } > imem


    __imem_end = .;


    ASSERT(
        __imem_end <= ORIGIN(imem) + LENGTH(imem),
        "ACT code exceeds IMEM"
    )


    _end = __stack_top;
}