SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

IVERILOG ?= iverilog
VVP ?= vvp
IVERILOG_FLAGS := -g2012
IVERILOG_WARN_FILTER := sed '/sorry: constant selects in always_[*] processes are not fully supported/d'

BUILD_DIR := build
TEST_TARGETS := test-alu test-next-pc test-immediate-gen test-sram test-memory-controller test-memory-controller-sram test-fetch test-regfile test-control test-csrfile test-trap-controller test-pma test-timer test-system-timer test
TEST_TARGET_COUNT := $(words $(TEST_TARGETS))

# These paths are evaluated from within $(ARCH_TEST_DIR).
ARCH_TEST_DIR ?= riscv-arch-test
ARCH_TEST_CONFIG ?= ../riscv-test-config/test_config.yaml
ARCH_TEST_RUN_CMD ?= ../riscv-test-config/run_cmd.txt
ARCH_TEST_ELF_DIR ?= work/jason-rv64i/elfs
ARCH_TEST_EXTENSIONS ?= I,Sm,Zicsr,Zicntr
ARCH_TEST_FAST ?= True
ARCH_TEST_TIMEOUT ?= 60

.PHONY: all core test test-all test-arch test-alu test-next-pc test-immediate-gen test-sram test-memory-controller test-memory-controller-sram test-ram test-fetch test-regfile test-control test-csrfile test-trap-controller test-pma test-timer test-system-timer clean

all: core

$(BUILD_DIR):
	mkdir -p $@

core: $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -s riscv_core -o $(BUILD_DIR)/riscv_core -f sim/rtl.f 2>&1 | $(IVERILOG_WARN_FILTER)

define RUN_TEST
	$(IVERILOG) $(IVERILOG_FLAGS) -s $(1) -o $(BUILD_DIR)/$(1) -f $(2) 2>&1 | $(IVERILOG_WARN_FILTER)
	$(VVP) $(BUILD_DIR)/$(1)
endef

test: $(BUILD_DIR)
	$(call RUN_TEST,tb_core,sim/tb_core.f)

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

# Build self-checking Architectural Certification Test ELFs, then run each on the RTL.
test-arch:
	$(MAKE) -C $(ARCH_TEST_DIR) EXTENSIONS=$(ARCH_TEST_EXTENSIONS) CONFIG_FILES=$(ARCH_TEST_CONFIG) DEBUG= FAST=$(ARCH_TEST_FAST)
	cd $(ARCH_TEST_DIR) && ./run_tests.py "$$(cat $(ARCH_TEST_RUN_CMD))" $(ARCH_TEST_ELF_DIR) --timeout $(ARCH_TEST_TIMEOUT)

test-alu: $(BUILD_DIR)
	$(call RUN_TEST,tb_alu,sim/tb_alu.f)

test-next-pc: $(BUILD_DIR)
	$(call RUN_TEST,tb_next_pc,sim/tb_next_pc.f)

test-immediate-gen: $(BUILD_DIR)
	$(call RUN_TEST,tb_immediate_gen,sim/tb_immediate_gen.f)

test-sram: $(BUILD_DIR)
	$(call RUN_TEST,tb_sram,sim/tb_sram.f)

test-memory-controller: $(BUILD_DIR)
	$(call RUN_TEST,tb_memory_controller,sim/tb_memory_controller.f)

test-memory-controller-sram: $(BUILD_DIR)
	$(call RUN_TEST,tb_memory_controller_sram,sim/tb_memory_controller_sram.f)

test-ram: test-sram

test-fetch: $(BUILD_DIR)
	$(call RUN_TEST,tb_fetch,sim/tb_fetch.f)

test-regfile: $(BUILD_DIR)
	$(call RUN_TEST,tb_regfile,sim/tb_regfile.f)

test-control: $(BUILD_DIR)
	$(call RUN_TEST,tb_control_unit,sim/tb_control_unit.f)

test-csrfile: $(BUILD_DIR)
	$(call RUN_TEST,tb_csrfile,sim/tb_csrfile.f)

test-trap-controller: $(BUILD_DIR)
	$(call RUN_TEST,tb_trap_controller,sim/tb_trap_controller.f)

test-pma: $(BUILD_DIR)
	$(call RUN_TEST,tb_pma_checker,sim/tb_pma_checker.f)

test-timer: $(BUILD_DIR)
	$(call RUN_TEST,tb_timer_interrupt,sim/tb_timer_interrupt.f)

test-system-timer: $(BUILD_DIR)
	$(call RUN_TEST,tb_riscv_system_timer,sim/tb_riscv_system_timer.f)

clean:
	rm -rf $(BUILD_DIR)
