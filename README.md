# Zynq-7020 FPGA + Embedded Linux Bring-Up

This repository is a Zynq-7020 bring-up project. Buildroot Linux runs on the
Zynq PS dual ARM Cortex-A9, while the PL sends a fixed AXI4-Stream frame to PS
DDR through Xilinx AXI DMA S2MM and HP0. The Linux side triggers one capture,
waits for DMA completion, checks the FFT result, and returns it through
`/dev/fft_dma0`.

The project is about the PS/PL boundary: the Vivado block design, Linux kernel
module, Device Tree binding, Buildroot integration, boot flow, and Ethernet
test path. Xilinx XFFT is used as an existing IP block to provide a realistic
stream workload. The FFT algorithm itself is not custom RTL in this project.

## Main parts

### FPGA

[`hardware/vivado/create_zynq7020_fft_linux.tcl`](hardware/vivado/create_zynq7020_fft_linux.tcl)
creates the Vivado design. It includes the AXI4-Stream source, FIFO, XFFT,
AXI DMA S2MM, HP0 connection, capture GPIO, and PL-to-PS interrupt. The
`axis_sample_sim` block produces a deterministic test frame; there is no ADC in
the current design.

### ARM Cortex-A9 and Embedded Linux

The Zynq PS runs Buildroot Linux for ARMv7 Cortex-A9. The external Buildroot
tree selects the kernel, root filesystem, module, user-space test tools, and
software-only SD image:

[`buildroot-external/configs/zynq7020_fft_defconfig`](buildroot-external/configs/zynq7020_fft_defconfig)

### Linux kernel and DMAengine

[`linux_driver/fft_dma_drv.c`](linux_driver/fft_dma_drv.c) is an out-of-tree
platform driver and DMAengine client. It owns the capture GPIO, coherent result
buffer, completion wait, result check, and `/dev/fft_dma0` ABI.

The in-kernel Xilinx DMAengine provider owns the AXI DMA register block and the
S2MM interrupt. One request follows this sequence:

```text
ioctl -> submit one S2MM descriptor -> assert capture -> wait for callback
      -> check residue and FFT peak -> return result
```

### Device Tree

The board DTS keeps the DMA controller and client as separate nodes:

```text
fft_dma client node
  -> dmas = <&axi_dma_fft 1>
  -> dma_request_chan(dev, "rx")
  -> Xilinx DMAengine provider
  -> AXI DMA S2MM channel
```

The same DTS also enables GEM0, the EMIO GMII-to-RGMII path, PHY reset, and the
Realtek PHY. See
[`buildroot-external/board/zynq7020/zynq7020-fft.dts`](buildroot-external/board/zynq7020/zynq7020-fft.dts).

### Ethernet

The PS GEM0 MAC is connected through EMIO and the PL GMII-to-RGMII bridge to
the board Ethernet PHY. Buildroot starts `fft_ethernet_server` on TCP port
5000 after network setup.

The startup script tries DHCP first. This works with a router or Windows
Internet Connection Sharing. Without DHCP, it falls back to the direct cable
address `192.168.7.2/24`; the PC USB Ethernet adapter uses `192.168.7.1/24`.

```powershell
.\scripts\set_direct_ethernet.ps1 -InterfaceAlias "<USB Ethernet alias>"
.\scripts\test_fft_over_ethernet.ps1
```

The endpoint accepts `PING`, `RUN`, `BENCH <iterations>`, and `NETCHECK`.
`RUN` performs one DMA-backed frame; `BENCH` runs the target benchmark;
`NETCHECK` verifies the target route and DNS resolution.

## Frame used for bring-up

The test source sends 1024 words per frame. Each word is 32 bits, so one DMA
transfer is 4096 bytes. The lower 16 bits hold the Q15 real value and the upper
16 bits are zero for the imaginary value. The 1000 ms timeout is a recovery
watchdog, not the expected transfer time. Shared definitions are in
[`include/uapi/fft_dma_uapi.h`](include/uapi/fft_dma_uapi.h).

## Boot and validation

QSPI contains the FSBL, PL bitstream, and U-Boot. Linux stays on the SD card:

```text
BootROM -> FSBL -> PL bitstream -> U-Boot -> SD kernel + DTB -> SD rootfs
```

JTAG is used first to load the bitstream, kernel, initramfs, and DTB without
writing QSPI or the SD card. After the JTAG test passes, the same software
payload is written to the SD card and tested again after normal boot.

Recorded DMAengine results:

| Test | Result |
| --- | --- |
| `BENCH 1000` | 1000 completed transfers; 0 timeout and DMA errors; 205.119 us mean latency; 18.891 MiB/s |
| `BENCH 10000` | 10000 completed transfers; 0 timeout and DMA errors; 205.413 us mean latency; 18.863 MiB/s |

These numbers measure one sequential 4096-byte transaction from trigger to
result return. They are not AXI DMA peak bandwidth or an ADC sample-rate claim.
The command log and timeout, IRQ, and Device Tree debugging notes are in
[`docs/DMAENGINE_DEBUG.md`](docs/DMAENGINE_DEBUG.md).

## Repository layout

| Path | Purpose |
| --- | --- |
| [`hardware/`](hardware) | Vivado Tcl, constraints, JTAG scripts, and PL sources |
| [`linux_driver/`](linux_driver) | DMAengine client kernel module |
| [`include/uapi/`](include/uapi) | Shared ioctl ABI and frame constants |
| [`linux_app/`](linux_app) | Smoke test, benchmark, and Ethernet server |
| [`buildroot-external/`](buildroot-external) | Buildroot packages, DTS, rootfs overlay, and image scripts |
| [`docs/`](docs) | Hardware notes, build steps, validation, and debugging records |
| [`scripts/`](scripts) | SD card and Ethernet test helpers |

## Limits

- The input is a synthetic PL source, not an external ADC.
- Transfers are sequential, one frame at a time. There is no cyclic DMA,
  scatter-gather user interface, or continuous acquisition path.
- XFFT is Xilinx IP used unchanged.

## Local check

```bash
./scripts/check_project.sh
```

For build and deployment commands, see
[`docs/BUILD_AND_DEPLOY.md`](docs/BUILD_AND_DEPLOY.md).
