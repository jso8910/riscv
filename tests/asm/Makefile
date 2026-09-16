RISCV_GCC ?= riscv64-unknown-elf-gcc
ARCH ?= rv64i_zmmul_zicsr
ABI ?= lp64
OUT ?= ../../build/pipeline_fault_regression.elf

.PHONY: all clean

all: $(OUT)

$(OUT): pipeline_fault_regression.S ../../riscv-test-config/link.ld

	@mkdir -p $(dir $@)
	$(RISCV_GCC) -nostdlib -nostartfiles -march=$(ARCH) -mabi=$(ABI) \
		-Wl,-T,../../riscv-test-config/link.ld -o $@ $<

clean:
	rm -f $(OUT)
