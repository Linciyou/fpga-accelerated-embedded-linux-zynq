# FPGA-Accelerated Embedded Linux System on Zynq

This project is a Zynq-7020 hardware/software integration exercise. Buildroot
Linux controls a one-frame PL-to-PS DMA path and exposes the result through a
small kernel driver.

The workload uses the Xilinx XFFT IP with a synthesizable sample generator. The
FFT algorithm and XFFT RTL are not the contribution here. The contribution is
the integration around it: PS/PL wiring, AXI DMA, Device Tree, a Linux
DMAengine client, Buildroot packaging, and repeatable board validation.

The first version directly operated the AXI DMA registers; the current version
uses the upstream Xilinx DMAengine provider with a custom client driver, while
the V1 source remains as historical evidence in
[`linux_driver/v1_register/`](linux_driver/v1_register/).

## What I built

- Integrated Zynq PS, AXI4-Stream source, FIFO, Xilinx XFFT IP, AXI DMA S2MM,
  HP0 DDR access, Ethernet, and UART in Vivado.
- Described the AXI DMA provider and client relationship in Device Tree.
- Implemented a small DMAengine client with a serialized ioctl path:
  `ioctl -> one frame -> wait for completion -> process -> return`.
- Built the kernel module, UAPI header, test client, benchmark, and Ethernet
  endpoint into a Buildroot image.
- Validated the same software payload first over JTAG and then from SD boot.

## DMA ownership

```text
Custom fft_dma driver
  |-- owns capture control register
  |-- owns coherent result buffer lifecycle
  |-- exposes /dev/fft_dma0
  |
  `-- DMAengine client
          |
          v
Xilinx AXI DMA Linux driver
  |-- owns AXI DMA registers
  |-- owns the S2MM IRQ
  `-- reports descriptor completion
```

The Device Tree path is:

```text
fft_dma client node
  -> dmas = <&axi_dma_fft 1>
  -> dma_request_chan(dev, "rx")
  -> Xilinx AXI DMAengine provider
  -> AXI DMA S2MM hardware
```

The custom driver does not map AXI DMA registers, acknowledge the DMA IRQ, or
expose DMA addresses to user space.

## Data path

```text
axis_sample_sim -> AXI4-Stream FIFO -> Xilinx XFFT -> AXI DMA S2MM
    -> Zynq HP0 -> coherent PS DDR buffer -> fft_dma_drv -> /dev/fft_dma0
```

The sample generator produces a deterministic Q15 frame. The frame is
`1024` 32-bit words, or `4096` bytes. That size matches the current PL test
stream and keeps one ioctl request bounded and easy to inspect. The driver
waits up to `1000 ms` as a transfer watchdog; this is an error recovery limit,
not an expected transfer time.

## Validation snapshot

- `10,000` consecutive DMA transfers
- `0` timeout / DMA errors
- About `205 us` mean end-to-end latency

The latency distribution, throughput, raw output, timeout record, IRQ record,
DT record, and SD-boot evidence are in
[`docs/DMAENGINE_V2_DEBUG.md`](docs/DMAENGINE_V2_DEBUG.md).

The reported throughput is sequential end-to-end transaction throughput, not
AXI DMA peak bandwidth.

## Boot and test

QSPI stores the existing FSBL, PL bitstream, and U-Boot. The software-only SD
image stores the Linux kernel, DTB, Buildroot root filesystem, driver, and test
applications.

```text
QSPI BootROM -> FSBL + PL bitstream -> U-Boot
             -> SD kernel + DTB -> SD rootfs -> /dev/fft_dma0
```

For a direct Ethernet test, use `192.168.7.1/24` on the PC adapter and
`192.168.7.2/24` on the board:

```powershell
.\scripts\set_direct_ethernet.ps1 -InterfaceAlias "<USB Ethernet alias>"
.\scripts\test_dmaengine_stress.ps1
```

The script sends `BENCH 1000` and `BENCH 10000` to the target endpoint.

## Limitations

- The input is a synthetic sample generator; no external ADC is connected.
- The driver performs sequential single-frame DMA, not continuous acquisition.
- The Xilinx XFFT IP is used as a workload; custom FFT RTL, radix design, and
  butterfly/pipeline architecture are outside this project scope.
- The benchmark does not establish multi-hour stability or analog signal
  quality.

## Repository layout

| Path | Contents |
| --- | --- |
| [`hardware/`](hardware) | RTL, Vivado Tcl, constraints, and JTAG scripts |
| [`linux_driver/`](linux_driver) | Active DMAengine client and historical V1 reference |
| [`include/uapi/`](include/uapi) | Shared ioctl and frame configuration |
| [`linux_app/`](linux_app) | Smoke test, benchmark, and Ethernet server |
| [`buildroot-external/`](buildroot-external) | Buildroot packages, DTB, and image scripts |
| [`docs/`](docs) | Linux integration, architecture, debug, and validation records |

## Development check

```bash
./scripts/check_project.sh
```

This checks shell syntax, whitespace, and host compilation of the user-space
clients. It does not replace target DMA validation.
