#!/usr/bin/env bash
# Run once inside Ubuntu 22.04 after WSL2 installation.
set -euo pipefail

sudo apt update
sudo apt install -y \
    build-essential git rsync cpio unzip bc file wget curl python3 \
    libncurses-dev bison flex libssl-dev device-tree-compiler dosfstools mtools

echo "Build dependencies installed."
