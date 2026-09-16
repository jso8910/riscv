ROOT := $(abspath ../..)
COREMARK_DIR := $(ROOT)/third_party/coremark
BUILD_DIR ?= $(ROOT)/build/bench/coremark
CC = riscv64-unknown-elf-gcc
ITERATIONS ?= 10
CLOCK_HZ ?= 1000000

COMMON_FLAGS := -std=gnu17 -O2 -ffreestanding -fno-builtin -fno-pic -fno-stack-protector \
  -ffunction-sections -fdata-sections -msmall-data-limit=0 \
  -march=rv64i_zmmul_zicsr_zicntr -mabi=lp64 -mcmodel=medany \
  -I$(COREMARK_DIR) -I$(ROOT)/bench/coremark -I$(ROOT)/bench/platform/include
CFLAGS := $(COMMON_FLAGS) -DPERFORMANCE_RUN=1 -DITERATIONS=$(ITERATIONS) \
  -DCOREMARK_CLOCK_HZ=$(CLOCK_HZ)ULL
LDFLAGS := -nostdlib -Wl,--gc-sections -Wl,-T,$(ROOT)/bench/embench/link.ld
SOURCES := $(COREMARK_DIR)/core_list_join.c $(COREMARK_DIR)/core_main.c \
  $(COREMARK_DIR)/core_matrix.c $(COREMARK_DIR)/core_state.c \
  $(COREMARK_DIR)/core_util.c $(ROOT)/bench/coremark/core_portme.c \
  $(ROOT)/bench/coremark/ee_printf.c $(ROOT)/bench/platform/benchmark.c \
  $(ROOT)/bench/platform/string.c $(ROOT)/bench/platform/softint.c $(ROOT)/bench/platform/ctype.c \
  $(ROOT)/bench/platform/softfloat.c \
  $(ROOT)/bench/platform/crt0.S

.PHONY: all run clean
all: $(BUILD_DIR)/coremark.elf

$(BUILD_DIR):
	mkdir -p $@

$(BUILD_DIR)/coremark.elf: $(SOURCES) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(SOURCES) $(LDFLAGS) -o $@

run: all
	python3 $(ROOT)/sim/run_benchmark.py --max-cycles 20000000 --json \
		--coremark-iterations $(ITERATIONS) $(BUILD_DIR)/coremark.elf

clean:
	rm -rf $(BUILD_DIR)
