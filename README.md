# Zynq-7020 FPGA + Embedded Linux DMA Path

This repository contains the hardware and software for a Zynq-7020 PL-to-PS
capture path. The PL produces a fixed AXI4-Stream frame, sends it through
Xilinx XFFT and AXI DMA S2MM, and writes the result into PS DDR through HP0.
Buildroot Linux exposes one capture through `/dev/fft_dma0`.

XFFT is Xilinx IP used as a realistic stream workload. The FFT algorithm and
RTL are not custom work in this repository. The work here is the PS/PL
integration, DMA path, Device Tree binding, Linux client driver, Buildroot
image, and board validation.

The first version directly operated AXI DMA registers. The active version uses
the upstream Xilinx DMAengine provider with a custom client driver; the old
source remains in [`linux_driver/v1_register/`](linux_driver/v1_register/) as a
historical reference.

## Design

```text
axis_sample_sim -> AXI4-Stream FIFO -> Xilinx XFFT -> AXI DMA S2MM
    -> Zynq HP0 -> coherent PS DDR buffer -> fft_dma_drv -> /dev/fft_dma0
```

The PL source is a deterministic Q15 sample generator. It sends one frame of
1024 32-bit words, so every DMA request is 4096 bytes. There is no external ADC
in this design.

## Linux DMA path

`fft_dma_drv` is a DMAengine client. Its user interface intentionally stays
small:

```text
ioctl -> start one frame -> wait for completion -> find peak -> return result
```

```text
Custom fft_dma driver
  |-- capture control register
  |-- coherent result buffer lifecycle
  |-- /dev/fft_dma0
  `-- DMAengine client
          |
          v
Xilinx AXI DMA Linux driver
  |-- AXI DMA registers
  |-- S2MM IRQ
  `-- DMA descriptor completion
```

The Device Tree relationship is deliberately kept separate from the DMA
provider:

```text
fft_dma client node
  -> dmas = <&axi_dma_fft 1>
  -> dma_request_chan(dev, "rx")
  -> Xilinx AXI DMAengine provider
  -> AXI DMA S2MM hardware
```

The client driver never maps AXI DMA registers, acknowledges the DMA IRQ, or
passes DMA addresses to user space. Those belong to the Xilinx DMAengine
provider.

## Frame contract

| Setting | Value | Reason |
| --- | --- | --- |
| `FFT_DMA_FRAME_SAMPLES` | 1024 | Matches the current PL frame and XFFT transform length. |
| `FFT_DMA_FRAME_BYTES` | 4096 | 1024 samples x 32-bit stream word. |
| `FFT_DMA_TIMEOUT_MS` | 1000 | Watchdog for recovery; not the expected transfer time. |

The definitions live in
[`include/uapi/fft_dma_uapi.h`](include/uapi/fft_dma_uapi.h), so the kernel
driver and user-space tests use the same values.

## Board validation

The DMAengine version was validated with the same target payload first through
JTAG and then after booting Linux from SD.

- 10,000 consecutive transfers
- 0 timeout or DMA errors
- About 205 us mean end-to-end latency

The result includes setup, trigger, DMA completion, and peak search. It is not
AXI DMA peak bandwidth. Raw output, latency and throughput details, and the
DMA timeout, IRQ, and Device Tree debugging notes are in
[`docs/DMAENGINE_V2_DEBUG.md`](docs/DMAENGINE_V2_DEBUG.md).

## Boot and test

QSPI contains the existing FSBL, PL bitstream, and U-Boot. The SD card is
software-only: kernel, DTB, Buildroot root filesystem, module, and test tools.

```text
QSPI BootROM -> FSBL + PL bitstream -> U-Boot
             -> SD kernel + DTB -> SD rootfs -> /dev/fft_dma0
```

The direct Ethernet test uses a PC USB Ethernet adapter connected directly to
the Zynq Ethernet port. No DHCP server or router is required.

```text
PC:    192.168.7.1/24
Board: 192.168.7.2/24
```

```powershell
.\scripts\set_direct_ethernet.ps1 -InterfaceAlias "<USB Ethernet alias>"
.\scripts\test_dmaengine_stress.ps1
```

The script sends `BENCH 1000` and `BENCH 10000` to the target endpoint.

## Scope

- Sequential one-frame DMA only; no continuous acquisition, cyclic DMA, or
  scatter-gather user interface.
- Synthetic source only; analog capture and ADC validation are out of scope.
- Xilinx XFFT is used unchanged. Custom FFT RTL, radix design, and pipeline
  architecture are outside the project.
- The stress test demonstrates 10,000 transfers, not multi-hour reliability.

## Repository map

| Path | Contents |
| --- | --- |
| [`hardware/`](hardware) | RTL, Vivado Tcl, constraints, and JTAG scripts |
| [`linux_driver/`](linux_driver) | Active DMAengine client and V1 reference |
| [`include/uapi/`](include/uapi) | Shared ioctl and frame configuration |
| [`linux_app/`](linux_app) | Smoke test, benchmark, and Ethernet server |
| [`buildroot-external/`](buildroot-external) | Buildroot packages, DTB, and image scripts |
| [`docs/`](docs) | Integration notes, debug records, and validation evidence |

## Development check

```bash
./scripts/check_project.sh
```

This checks shell syntax, whitespace, and host compilation of the user-space
clients. It does not replace target DMA validation.
