# Linux Integration

The Linux implementation uses a DMAengine client design. The standard Xilinx
DMAengine provider owns the AXI DMA controller; `fft_dma_drv` owns the capture
trigger, buffer lifecycle, result checking, and `/dev/fft_dma0` ABI.

## Ownership split

| Layer | Responsibility | Main files |
| --- | --- | --- |
| Vivado design | AXI DMA S2MM, capture GPIO, and F2P IRQ | `hardware/vivado/create_zynq7020_fft_linux.tcl` |
| Xilinx DMA provider | AXI DMA registers, descriptor execution, and S2MM IRQ | Kernel `CONFIG_XILINX_DMA` |
| Device Tree | Bind the provider and client to the same S2MM channel | `buildroot-external/board/zynq7020/zynq7020-fft.dts` |
| DMAengine client | Submit one S2MM descriptor and analyse its coherent buffer | `linux_driver/fft_dma_drv.c` |
| UAPI | Shared ioctl and result structure | `include/uapi/fft_dma_uapi.h` |
| User space | Smoke test, benchmark, and Ethernet control | `linux_app/` |

## Device Tree contract

`axi_dma_fft` is a standard `xlnx,axi-dma-1.00.a` controller. Its S2MM child
has the GIC SPI 29 interrupt. The Xilinx provider registers this direction as
DMA channel `1`.

`fft_dma` is the client node. It contains the capture GPIO `reg`,
`dmas = <&axi_dma_fft 1>`, and `dma-names = "rx"`. The lookup path is:

```text
fft_dma client -> dmas channel 1 -> dma_request_chan("rx")
              -> Xilinx DMAengine provider -> AXI DMA S2MM
```

`dma_request_chan(..., "rx")` defers until the provider is ready and fails
probe if the binding is malformed.

The AXI DMA provider has all four clock names required by the Xilinx Linux driver. They use the existing 100 MHz PS FCLK; MM2S and SG are not enabled in hardware, but the provider requests named clock handles during probe.

## Transfer lifecycle

1. The client allocates its `FFT_DMA_FRAME_BYTES` buffer with
   `dma_alloc_coherent()` using the DMAengine device.
2. It configures the channel for `DMA_DEV_TO_MEM` with a 32-bit stream width.
3. It prepares and submits one `FFT_DMA_FRAME_BYTES` S2MM descriptor, then
   issues it.
4. It asserts capture only after the descriptor is pending, then waits up to one second for the DMAengine callback.
5. On timeout or DMAengine error it deasserts capture and calls `dmaengine_terminate_sync()`.
6. On completion it verifies zero residue, calculates the FFT peak, and copies the small result structure to user space.

The custom client never maps AXI DMA registers and never owns the S2MM IRQ. User space never programs DMA addresses or uses `/dev/mem`.

## Frame configuration

The shared UAPI header defines the fixed test contract:

| Setting | Value | Reason |
| --- | --- | --- |
| `FFT_DMA_FRAME_SAMPLES` | `1024` | Current PL sample frame and Xilinx XFFT transform length |
| `FFT_DMA_FRAME_BYTES` | `4096` | 1024 stream words at 32 bits per word |
| `FFT_DMA_TIMEOUT_MS` | `1000` | Watchdog for a missing completion, not a transfer target |

The frame size is a workload choice, not a claim about continuous ADC rate.
The Xilinx XFFT IP exercises the stream; FFT RTL design is outside the Linux
driver contribution.

## User-space ABI

`FFT_DMA_IOCTL_RUN` returns `struct fft_dma_result`. `dma_status` is
`FFT_DMA_STATUS_COMPLETE` only after a complete DMAengine transfer.
`bytes_received` must be `FFT_DMA_FRAME_BYTES` and the deterministic workload
must peak at `FFT_DMA_EXPECTED_PEAK_BIN`.

The ioctl returns `-ETIMEDOUT` when the callback is absent, `-EIO` when DMAengine reports incomplete/error status or non-zero residue, `-ENOTTY` for an unknown ioctl, and the DMAengine return code for descriptor setup errors.

## Buildroot packages

| Package | Target file | Purpose |
| --- | --- | --- |
| `fft-dma-uapi` | staging header | Shared UAPI for module and applications |
| `fft-dma-driver` | `fft_dma_drv.ko` | DMAengine client module |
| `fft-dma-test` | `/usr/bin/fft_dma_test` | Single-transfer smoke test |
| `fft-dma-bench` | `/usr/bin/fft_dma_bench` | Latency, throughput, and stress benchmark |
| `fft-ethernet-server` | `/usr/sbin/fft_ethernet_server` | `PING`, `RUN`, `BENCH <iterations>`, and `NETCHECK` endpoint |

After changing a local package, rebuild the affected Buildroot packages from the Linux-native workspace. Use the JTAG-first procedure in [DMAENGINE_DEBUG.md](DMAENGINE_DEBUG.md) before producing an SD image.
