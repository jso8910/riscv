```sh
sudo apt-get update
sudo apt-get install -y git make python3 verilator scons gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf
git submodule update --init --recursive
make bench-coremark
make bench-coremark-run
make bench-embench
bench/run_embench.sh --relative
```
