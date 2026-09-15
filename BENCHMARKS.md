```sh
sudo apt-get update
sudo apt-get install -y git make python3 verilator scons gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf
git submodule update --init --recursive
make bench-coremark
make bench-coremark-run
make bench-embench
bench/run_embench.sh --relative
```

Benchmark progression

eaf72ff: RV64I, 5 stage pipeline, no branch prediction, no multiply. Software multiply approach was
radix-4 shift/add multiplier.

| Commit hash | Core frequency | Embench | Coremarks/MHz |
| -------- | -------- | -------- | -------- |
| eaf72f    | DATA     | 0.48     | 0.786164 |
