#!/usr/bin/env sh
set -eu

target_dir="$1"

rm -f "$target_dir/root/BOOT_QSPI.bin"

if [ -n "${QSPI_BOOT_IMAGE:-}" ]; then
	test -f "$QSPI_BOOT_IMAGE"
	install -D -m 0644 "$QSPI_BOOT_IMAGE" "$target_dir/root/BOOT_QSPI.bin"
fi

chmod 0755 "$target_dir/etc/init.d/S39qspi-program"
chmod 0755 "$target_dir/etc/init.d/S40fft-dma"
chmod 0755 "$target_dir/etc/init.d/S41ethernet"
chmod 0755 "$target_dir/etc/init.d/S60fft-ethernet"
