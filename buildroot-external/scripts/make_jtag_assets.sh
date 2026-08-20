#!/usr/bin/env bash
# Produce a raw zImage and a DTB that describes the initramfs loaded by JTAG.
set -euo pipefail

images_dir=${1:?Usage: make_jtag_assets.sh <buildroot-images-dir>}
build_dir=$(dirname "$images_dir")
linux_dir="$build_dir/build/linux-custom"
fdtput_bin="$build_dir/host/bin/fdtput"
initrd_addr=0x06000000

test -x "$fdtput_bin" || { echo "Missing fdtput: $fdtput_bin" >&2; exit 1; }
test -f "$linux_dir/arch/arm/boot/zImage" || { echo "Missing zImage" >&2; exit 1; }
test -f "$images_dir/rootfs.cpio.gz" || { echo "Missing rootfs.cpio.gz" >&2; exit 1; }
test -f "$images_dir/zynq7020-fft.dtb" || { echo "Missing zynq7020-fft.dtb" >&2; exit 1; }

initrd_size=$(stat -c %s "$images_dir/rootfs.cpio.gz")
initrd_end=$(printf '0x%08x' $((initrd_addr + initrd_size)))

cp "$linux_dir/arch/arm/boot/zImage" "$images_dir/zImage"
cp "$images_dir/zynq7020-fft.dtb" "$images_dir/zynq7020-fft-jtag.dtb"
cp "$images_dir/zynq7020-fft.dtb" "$images_dir/zynq7020-fft-qspi-program.dtb"
"$fdtput_bin" -t s "$images_dir/zynq7020-fft-jtag.dtb" /chosen bootargs \
    "console=ttyPS1,115200 root=/dev/ram rw"
"$fdtput_bin" -t x "$images_dir/zynq7020-fft-jtag.dtb" /chosen linux,initrd-start "$initrd_addr"
"$fdtput_bin" -t x "$images_dir/zynq7020-fft-jtag.dtb" /chosen linux,initrd-end "$initrd_end"

"$fdtput_bin" -t s "$images_dir/zynq7020-fft-qspi-program.dtb" /chosen bootargs \
    "console=ttyPS1,115200 root=/dev/ram rw qspi_program=1"
"$fdtput_bin" -t x "$images_dir/zynq7020-fft-qspi-program.dtb" /chosen linux,initrd-start "$initrd_addr"
"$fdtput_bin" -t x "$images_dir/zynq7020-fft-qspi-program.dtb" /chosen linux,initrd-end "$initrd_end"

echo "Created JTAG assets with initrd range $initrd_addr-$initrd_end"
