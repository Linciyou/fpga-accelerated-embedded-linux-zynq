# Build: Zynq-7020 FPGA + Embedded Linux

## Host prerequisites

- Windows: AMD Vivado and Vitis 2025.2 (default path
  `C:\AMDDesignTools\2025.2`)
- Linux build host: WSL2 Ubuntu 22.04 or equivalent
- Board: Zynq-7020 board with QSPI, SD card, JTAG, and direct Ethernet cable

If AMD tools are installed elsewhere, set `AMD_TOOLS_ROOT` before running the
Vitis Tcl scripts.

## Build the FPGA design

From PowerShell:

```powershell
& 'C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat' -mode batch -source .\hardware\vivado\create_zynq7020_fft_linux.tcl
```

The generated bitstream is used to package the QSPI boot image. Inspect the
Vivado implementation report before programming hardware.

## Build Buildroot

Keep the active Buildroot workspace on the Linux filesystem:

```bash
rsync -a --exclude build /mnt/c/Users/<user>/zynq7020/ ~/work/zynq7020/
cd ~/work/zynq7020
./buildroot-external/scripts/setup_ubuntu.sh
./buildroot-external/scripts/bootstrap_buildroot.sh
```

The outputs are placed under `build/buildroot-zynq7020/images/` in the Linux
workspace. Buildroot is the only maintained Linux build flow in this repository.

## Package QSPI boot firmware

Generate the FSBL after exporting the XSA, then copy Buildroot's `u-boot.bin`
to `build/linux_images/` and package the QSPI image:

```powershell
& 'C:\AMDDesignTools\2025.2\Vitis\bin\xsct.bat' .\hardware\vivado\create_zynq_fsbl.tcl
& 'C:\AMDDesignTools\2025.2\Vitis\bin\xsct.bat' .\hardware\vivado\package_qspi_boot.tcl
```

This creates `build/flash_images/BOOT_QSPI.bin`, containing FSBL, the PL
bitstream, and U-Boot. Linux remains on SD.

The checked-in JTAG programmer uses a temporary Linux initramfs plus the
kernel SPI-NOR driver to program QSPI:

```powershell
& 'C:\AMDDesignTools\2025.2\Vitis\bin\xsct.bat' .\hardware\vivado\jtag_program_qspi_linux.tcl
```

## Create and write the software-only SD image

Generate the SD image after Buildroot produces `uImage`, DTB, rootfs, and
`extlinux.conf`:

```bash
./buildroot-external/scripts/make_sd_image.sh build/buildroot-zynq7020/images
```

On Windows, write only to the confirmed non-system USB reader:

```powershell
.\scripts\write_sdcard.ps1 -DiskNumber <n>
.\scripts\verify_sdcard.ps1 -DiskNumber <n>
```

`write_sdcard.ps1` refuses system or non-USB disks. Always confirm the disk
number before writing.

## Run the functional test

Set the direct-link address on the PC, then invoke the Ethernet test:

```powershell
.\scripts\set_direct_ethernet.ps1 -InterfaceAlias "<USB Ethernet alias>"
.\scripts\test_fft_over_ethernet.ps1
```

For a direct PC-to-board link with Internet access, configure the PC USB
Ethernet adapter as the NAT gateway at `192.168.7.1`, then use:

```powershell
.\scripts\test_fft_over_ethernet.ps1 -VerifyInternet
```

With a DHCP-enabled router or Windows Internet Connection Sharing, the board
uses the lease-provided address, route, and DNS settings instead.

For JTAG boot-state inspection, use `hardware/vivado/jtag_boot_mode_state.tcl`.
