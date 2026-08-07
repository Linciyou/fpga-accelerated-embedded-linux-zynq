#!/usr/bin/env bash
# Create the software-only SD image used after QSPI has loaded U-Boot.
set -euo pipefail

images_dir=${1:?Usage: make_sd_image.sh <buildroot-images-dir>}
genimage_bin="$(dirname "$images_dir")/host/bin/genimage"
work_dir="$(dirname "$images_dir")/.genimage-zynq7020-work"
root_dir="$(dirname "$images_dir")/.genimage-zynq7020-root"
config_file="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/board/zynq7020/genimage.cfg"

test -x "$genimage_bin" || { echo "Missing Buildroot genimage: $genimage_bin" >&2; exit 1; }
for file in uImage zynq7020-fft.dtb rootfs.ext4 extlinux.conf; do
    test -f "$images_dir/$file" || { echo "Missing $images_dir/$file" >&2; exit 1; }
done

rm -rf "$work_dir" "$root_dir"
mkdir -p "$root_dir" "$images_dir/extlinux"
cp "$images_dir/extlinux.conf" "$images_dir/extlinux/extlinux.conf"
"$genimage_bin" --rootpath "$root_dir" --tmppath "$work_dir" \
    --inputpath "$images_dir" --outputpath "$images_dir" --config "$config_file"

echo "Created $images_dir/sdcard.img"
