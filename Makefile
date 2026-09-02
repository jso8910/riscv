SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

IVERILOG ?= iverilog
VVP      ?= vvp
IVERILOG_WARN_FILTER := sed '/sorry: constant selects in always_[*] processes are not fully supported/d'

BUILD_DIR := build
CORE_OUT  := $(BUILD_DIR)/core.vvp
ALU_OUT   := $(BUILD_DIR)/tb_alu.vvp
NEXT_PC_OUT := $(BUILD_DIR)/tb_next_pc.vvp
IMMEDIATE_GEN_OUT := $(BUILD_DIR)/tb_immediate_gen.vvp
SRAM_OUT  := $(BUILD_DIR)/tb_sram.vvp
MEM_CTRL_OUT := $(BUILD_DIR)/tb_memory_controller.vvp
MEM_CTRL_SRAM_OUT := $(BUILD_DIR)/tb_memory_controller_sram.vvp
FETCH_OUT := $(BUILD_DIR)/tb_fetch.vvp
REGFILE_OUT := $(BUILD_DIR)/tb_regfile.vvp
TEST_OUT  := $(BUILD_DIR)/tb_core.vvp
TEST_TARGETS := test-alu test-next-pc test-immediate-gen test-sram test-memory-controller test-memory-controller-sram test-fetch test-regfile test
TEST_TARGET_COUNT := $(words $(TEST_TARGETS))

.PHONY: all core test test-all test-alu test-next-pc test-immediate-gen test-sram test-memory-controller test-memory-controller-sram test-ram test-fetch test-regfile clean

all: core

$(BUILD_DIR):
	mkdir -p $@

core: $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s riscv_core -o $(CORE_OUT) -f sim/rtl.f 2>&1 | $(IVERILOG_WARN_FILTER)

test: $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s tb_core -o $(TEST_OUT) -f sim/tb_core.f 2>&1 | $(IVERILOG_WARN_FILTER)
	$(VVP) $(TEST_OUT)

test-all: $(BUILD_DIR)
	@passed=0; failed=0; passed_tests=""; failed_tests=""; \
	for test in $(TEST_TARGETS); do \
		printf '\n==== %s ====\n' "$$test"; \
		if $(MAKE) $$test; then \
			passed=$$((passed + 1)); \
			passed_tests="$$passed_tests $$test"; \
		else \
			failed=$$((failed + 1)); \
			failed_tests="$$failed_tests $$test"; \
		fi; \
	done; \
	printf '\nTest summary:\n'; \
	printf '  Suites passed: %s/%s\n' "$$passed" "$(TEST_TARGET_COUNT)"; \
	printf '  Passed:%s\n' "$$passed_tests"; \
	if [ "$$failed" -gt 0 ]; then \
		printf '  Failed:%s\n' "$$failed_tests"; \
		exit 1; \
	fi

test-alu: $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s tb_alu -o $(ALU_OUT) -f sim/tb_alu.f 2>&1 | $(IVERILOG_WARN_FILTER)
	$(VVP) $(ALU_OUT)

test-next-pc: $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s tb_next_pc -o $(NEXT_PC_OUT) -f sim/tb_next_pc.f 2>&1 | $(IVERILOG_WARN_FILTER)
	$(VVP) $(NEXT_PC_OUT)

test-immediate-gen: $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s tb_immediate_gen -o $(IMMEDIATE_GEN_OUT) -f sim/tb_immediate_gen.f 2>&1 | $(IVERILOG_WARN_FILTER)
	$(VVP) $(IMMEDIATE_GEN_OUT)

test-sram: $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s tb_sram -o $(SRAM_OUT) -f sim/tb_sram.f 2>&1 | $(IVERILOG_WARN_FILTER)
	$(VVP) $(SRAM_OUT)

test-memory-controller: $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s tb_memory_controller -o $(MEM_CTRL_OUT) -f sim/tb_memory_controller.f 2>&1 | $(IVERILOG_WARN_FILTER)
	$(VVP) $(MEM_CTRL_OUT)

test-memory-controller-sram: $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s tb_memory_controller_sram -o $(MEM_CTRL_SRAM_OUT) -f sim/tb_memory_controller_sram.f 2>&1 | $(IVERILOG_WARN_FILTER)
	$(VVP) $(MEM_CTRL_SRAM_OUT)

test-ram: test-sram

test-fetch: $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s tb_fetch -o $(FETCH_OUT) -f sim/tb_fetch.f 2>&1 | $(IVERILOG_WARN_FILTER)
	$(VVP) $(FETCH_OUT)

test-regfile: $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s tb_regfile -o $(REGFILE_OUT) -f sim/tb_regfile.f 2>&1 | $(IVERILOG_WARN_FILTER)
	$(VVP) $(REGFILE_OUT)

clean:
	rm -rf $(BUILD_DIR)
