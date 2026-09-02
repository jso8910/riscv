```
yay -S --needed --noconfirm riscv-gnu-toolchain-bin

curl --location https://github.com/riscv/sail-riscv/releases/download/0.13.1/sail-riscv-$(uname)-$(arch).tar.gz | sudo tar xvz --directory=/usr/local/bin --strip-components=1

make -C riscv-arch-test EXTENSIONS=I CONFIG_FILES=../riscv-test-config/test_config.yaml FAST=True DEBUG=

cd riscv-arch-test
./run_tests.py "$(cat ../riscv-test-config/run_cmd.txt)" work/jason-rv32i/elfs --jobs 4 --timeout 60
```
