# Zynq-7020 FPGA + Embedded Linux Buildroot

This is the low-resource Embedded Linux flow for the simulated-sampler FFT
design. Buildroot runs in WSL2/Ubuntu; Vivado, Vitis FSBL generation, Bootgen,
and JTAG remain on Windows.

## One-time Windows setup

Open an elevated PowerShell in the repository and run:

```powershell
wsl --set-default-version 2
wsl --install -d Ubuntu-22.04
```

Restart Windows if the WSL installation requests it.

## One-time Ubuntu setup

Keep the working tree on the Linux filesystem, not `/mnt/c`:

```bash
mkdir -p ~/work
rsync -a --exclude build /mnt/c/Users/<windows-user>/zynq7020/ ~/work/zynq7020/
cd ~/work/zynq7020
./buildroot-external/scripts/setup_ubuntu.sh
```

## Build Linux

```bash
cd ~/work/zynq7020
./buildroot-external/scripts/bootstrap_buildroot.sh
```

The first build downloads the toolchain, Linux, and U-Boot. Outputs are in:

```text
build/buildroot-zynq7020/images/
```

It contains `uImage`, `zynq7020-fft.dtb`, `rootfs.ext4`, `u-boot.elf`, and
`extlinux.conf`.

It also contains `rootfs.cpio.gz` and `uRamdisk` for a no-SD JTAG boot. Create
the raw kernel and DTB with:

```bash
./buildroot-external/scripts/make_jtag_assets.sh build/buildroot-zynq7020/images
```

## Package QSPI boot firmware on Windows

The existing FSBL and bitstream are used so DDR and PS MIO configuration remain
identical to the Vivado design. Copy Buildroot's `u-boot.bin` to
`build/linux_images/`, generate the FSBL, then package the QSPI image from
PowerShell:

```powershell
& 'C:\AMDDesignTools\2025.2\Vitis\bin\xsct.bat' .\hardware\vivado\create_zynq_fsbl.tcl
& 'C:\AMDDesignTools\2025.2\Vitis\bin\xsct.bat' .\hardware\vivado\package_qspi_boot.tcl
```

Back in Ubuntu, create the software-only SD image:

```bash
cd ~/work/zynq7020
./buildroot-external/scripts/make_sd_image.sh build/buildroot-zynq7020/images
```

Flash `build/buildroot-zynq7020/images/sdcard.img` to an SD card. This is a
software-only image: the first partition holds the kernel, Device Tree, and
extlinux configuration; the second holds the Buildroot root filesystem. It
does not contain `BOOT.BIN`, FSBL, a PL bitstream, or U-Boot.

`build/flash_images/BOOT_QSPI.bin` contains FSBL, the PL bitstream, and U-Boot
only. The board boots QSPI with SW3-1 ON and SW3-2 OFF; U-Boot then loads the
kernel and Device Tree from the SD FAT partition and mounts the ext4 root
filesystem as `/dev/mmcblk0p2`.

The Device Tree exposes a 6 MiB `qspi-boot` MTD partition. The guarded
`S39qspi-program` init script runs only when the JTAG initramfs command line
contains `qspi_program=1`, and uses `flashcp -v` to program and verify QSPI.

## Target test

On the serial console, run:

```sh
fft_dma_test
```

This test opens `/dev/fft_dma0` and invokes the `FFT_DMA_IOCTL_RUN` ioctl. The
kernel module is a DMAengine client: it requests the Xilinx AXI DMA S2MM
channel, allocates a coherent 4 KiB buffer with the DMAengine device, submits a
descriptor, waits for its callback, and returns the calculated FFT peak to user
space. No application-level `/dev/mem` DMA access is used.

Expected result: `Peak bin: 1` and exit status zero. The module is packaged as
`fft_dma_drv.ko` is loaded by `/etc/init.d/S40fft-dma` and binds the
`bghjn,zynq7020-fft-dmaengine-2.0` client node. The standard
`xlnx,axi-dma-1.00.a` Device Tree node provides the AXI DMA registers and S2MM
interrupt; the client node provides the capture GPIO and DMA channel reference.
The production SD image starts the direct Ethernet endpoint instead of the
legacy JTAG result runner.

## Direct Ethernet test

`fft_ethernet_server` starts after the static `eth0` configuration. It listens
on TCP port 5000 and accepts `PING`, `RUN`, and `BENCH <iterations>` commands.
`RUN` invokes the same `/dev/fft_dma0` kernel ioctl as `fft_dma_test`; `BENCH`
runs the target-side DMAengine latency and throughput test.

Use the isolated direct-link addresses below; do not configure a gateway or
DHCP client:

```text
PC USB Ethernet adapter: 192.168.7.1/24
Zynq eth0:               192.168.7.2/24
```

The FPGA image exposes PS GEM0 through EMIO and the PL GMII-to-RGMII bridge to
the board RTL8211E PHY. The matching Device Tree enables the MAC, converter,
PHY reset GPIO, and Realtek PHY driver.
