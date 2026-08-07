#!/usr/bin/env sh
set -eu

images_dir="$1"
u_boot_elf=$(find "$BUILD_DIR" -maxdepth 2 -type f -name u-boot -print -quit)

if [ -z "$u_boot_elf" ]; then
    echo "Unable to find the U-Boot ELF in $BUILD_DIR" >&2
    exit 1
fi

cp "$u_boot_elf" "$images_dir/u-boot.elf"
cp "$BR2_EXTERNAL_ZYNQ7020_PATH/board/zynq7020/extlinux.conf" "$images_dir/extlinux.conf"

if [ -f "$images_dir/rootfs.cpio.gz" ]; then
    "$HOST_DIR/bin/mkimage" -A arm -O linux -T ramdisk -C gzip \
        -n "Zynq-7020 FFT Buildroot initramfs" \
        -d "$images_dir/rootfs.cpio.gz" "$images_dir/uRamdisk"
fi
