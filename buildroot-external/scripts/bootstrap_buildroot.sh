#!/usr/bin/env bash
# Run from a Linux-native checkout, not from /mnt/c.
set -euo pipefail

# WSL inherits Windows PATH entries containing spaces. Buildroot rejects those
# entries, so use only the standard Linux tool locations for the build.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
buildroot_dir="$root_dir/.buildroot/buildroot-2026.05"
output_dir="$root_dir/build/buildroot-zynq7020"

if [[ "$root_dir" == /mnt/* ]]; then
    echo "Move this repository under your Linux home directory before building." >&2
    exit 1
fi

if [ ! -d "$buildroot_dir/.git" ]; then
    mkdir -p "$(dirname "$buildroot_dir")"
    git clone --depth 1 --branch 2026.05 https://gitlab.com/buildroot.org/buildroot.git "$buildroot_dir"
fi

make -C "$buildroot_dir" O="$output_dir" \
    BR2_EXTERNAL="$root_dir/buildroot-external" zynq7020_fft_defconfig
make -C "$output_dir"

echo "Build complete: $output_dir/images"
echo "Next, package the QSPI image on Windows with hardware/vivado/package_qspi_boot.tcl."
