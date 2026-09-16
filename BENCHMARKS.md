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

131e4b3: RV64I, 5 stage pipeline, no branch prediction, no multiply. Software multiply approach was radix-4 shift/add multiplier.

___: RV64I with Zmmul extension, 7 stage pipeline, no branch prediction, radix-4 Booth-encoded Dadda tree multiplier.

| Commit hash | Core frequency | Embench | Coremarks/MHz |
| -------- | -------- | -------- | -------- |
| 131e4b3  | DATA     | 0.48     | 0.786164 |
| b3b4a15  | N/A      | 0.81     | 1.663659 |
