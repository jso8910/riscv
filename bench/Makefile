ROOT := $(abspath ..)

.PHONY: coremark coremark-run embench-build embench-run

coremark:
	$(MAKE) -C coremark

coremark-run:
	$(MAKE) -C coremark run

embench-build:
	$(ROOT)/bench/build_embench.sh

embench-run:
	$(ROOT)/bench/run_embench.sh
