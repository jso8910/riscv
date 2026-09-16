SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

IVERILOG ?= iverilog
VVP ?= vvp
VERILATOR ?= verilator
IVERILOG_FLAGS := -g2012
IVERILOG_WARN_FILTER := sed '/sorry: constant selects in always_[*] processes are not fully supported/d'

BUILD_DIR := build
TEST_TARGETS := test-alu test-next-pc test-immediate-gen test-booth-encoder-radix4 test-booth-partial-products test-dadda-stage test-sram test-memory-controller test-memory-controller-sram test-fetch test-regfile test-control test-csrfile test-trap-controller test-pma test-tlb test-timer test-system-timer test-csr-val-gen test-forwarding-hazard test-control-helpers test-pipeline-regs test test-pipeline-fault-regression
TEST_TARGET_COUNT := $(words $(TEST_TARGETS))

# These paths are evaluated from within $(ARCH_TEST_DIR).
ARCH_TEST_DIR ?= riscv-arch-test
ARCH_TEST_CONFIG ?= ../riscv-test-config/test_config.yaml
ARCH_TEST_RUN_CMD ?= ../riscv-test-config/run_cmd.txt
ARCH_TEST_ELF_DIR ?= work/jason-rv64izmmulsu-sv39/elfs
# Keep this aligned with riscv-test-config/jason-rv64i.yaml.  The privileged
# coverage includes U/S execution, Sstc, Sv39 translation, Svade A/D faults, and
# Bare satp mode in addition to the base machine-mode/CSR/counter coverage.
ARCH_TEST_EXTENSIONS ?= I,Zmmul,Sm,Zicsr,Zicntr,Zihpm,U,S,Sstc,Sv39,Svade,Svbare
ARCH_TEST_FAST ?= True
ARCH_TEST_TIMEOUT ?= 60
PIPELINE_FAULT_MAX_CYCLES ?= 100000

.PHONY: all core test test-all test-arch test-alu test-next-pc test-immediate-gen test-booth-encoder-radix4 test-booth-partial-products test-dadda-stage test-sram test-memory-controller test-memory-controller-sram test-ram test-fetch test-regfile test-control test-csrfile test-trap-controller test-pma test-tlb test-timer test-system-timer test-csr-val-gen test-forwarding-hazard test-control-helpers test-pipeline-regs test-pipeline-fault-regression bench-coremark bench-coremark-run bench-embench bench-embench-run clean

all: core

$(BUILD_DIR):
	mkdir -p $@

core: $(BUILD_DIR)
	$(VERILATOR) --lint-only --sv -Wno-fatal --top-module riscv_core -f sim/rtl.f

define RUN_TEST
	$(VERILATOR) --binary --timing --sv -Wno-fatal --top-module $(1) --Mdir $(BUILD_DIR)/obj_$(1) -f $(2)
	$(BUILD_DIR)/obj_$(1)/V$(1)
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

test-booth-encoder-radix4: $(BUILD_DIR)
	$(call RUN_TEST,tb_booth_encoder_radix4,sim/tb_booth_encoder_radix4.f)

test-booth-partial-products: $(BUILD_DIR)
	$(call RUN_TEST,tb_booth_partial_products,sim/tb_booth_partial_products.f)

test-dadda-stage: $(BUILD_DIR)
	$(call RUN_TEST,tb_dadda_stage,sim/tb_dadda_stage.f)

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

test-tlb: $(BUILD_DIR)
	$(call RUN_TEST,tb_tlb,sim/tb_tlb.f)

test-timer: $(BUILD_DIR)
	$(call RUN_TEST,tb_timer_interrupt,sim/tb_timer_interrupt.f)

test-system-timer: $(BUILD_DIR)
	$(call RUN_TEST,tb_riscv_system_timer,sim/tb_riscv_system_timer.f)

test-csr-val-gen: $(BUILD_DIR)
	$(call RUN_TEST,tb_csr_val_gen,sim/tb_csr_val_gen.f)

test-forwarding-hazard: $(BUILD_DIR)
	$(call RUN_TEST,tb_forwarding_hazard,sim/tb_forwarding_hazard.f)

test-control-helpers: $(BUILD_DIR)
	$(call RUN_TEST,tb_control_helpers,sim/tb_control_helpers.f)

test-pipeline-regs: $(BUILD_DIR)
	$(call RUN_TEST,tb_pipeline_regs,sim/tb_pipeline_regs.f)

# Bare-metal regression for integer dependencies and precise Sv39/PMP faults.
# It shares the cached Verilator architecture-test model used by test-arch and
# the benchmark runners.
test-pipeline-fault-regression:
	$(MAKE) -C tests/asm
	python3 sim/run_arch_test.py --simulator verilator --max-cycles $(PIPELINE_FAULT_MAX_CYCLES) build/pipeline_fault_regression.elf

# Bare-metal benchmark flows.  CoreMark and Embench sources are pinned as
# submodules; run `git submodule update --init --recursive` after cloning.
bench-coremark:
	$(MAKE) -C bench/coremark all

bench-coremark-run:
	$(MAKE) -C bench/coremark run

bench-embench:
	bench/build_embench.sh

bench-embench-run:
	bench/run_embench.sh --relative

clean:
	rm -rf $(BUILD_DIR)
