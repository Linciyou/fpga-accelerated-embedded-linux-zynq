# Linux Integration

This project focuses on the Linux boundary between PL hardware and a maintainable software stack.

## Ownership split

| Layer | Responsibility | Main files |
| --- | --- | --- |
| Vivado design | AXI DMA S2MM registers, capture GPIO, and F2P IRQ | `hardware/vivado/create_zynq7020_fft_linux.tcl` |
| Device Tree | MMIO resources and interrupt used by the driver | `buildroot-external/board/zynq7020/zynq7020-fft.dts` |
| Kernel driver | DMA programming, DMA memory, serialization, and completion | `linux_driver/fft_dma_drv.c` |
| UAPI | Shared ioctl and result structure | `include/uapi/fft_dma_uapi.h` |
| User space | Start a run and consume the constrained result API | `linux_app/fft_dma_test.c`, `linux_app/fft_ethernet_server.c` |
| Buildroot | Build the module and applications into the root filesystem | `buildroot-external/package/` |

The application never programs AXI DMA registers or DMA addresses. Those are owned by the kernel driver.

## Device Tree contract

The `bghjn,zynq7020-fft-dma-1.0` node must provide the resources below. The driver fails probe when a required resource is absent.

| Resource | DTS property | Driver use |
| --- | --- | --- |
| AXI DMA registers | first `reg`, named `dma` | Reset S2MM, set address and length, read/ack status |
| Capture GPIO registers | second `reg`, named `capture` | Gate the simulated source for one frame |
| S2MM interrupt | `interrupts` | Complete a blocked ioctl after success or error |

The driver calls `dma_set_mask_and_coherent(..., DMA_BIT_MASK(32))` and allocates its 4 KiB transfer buffer with `dma_alloc_coherent()`. The DTS does not reserve a fixed buffer because the driver receives a dynamic coherent DMA address from Linux. The board test recorded `0x1F042000`; that is evidence of runtime allocation, not a fixed ABI value.

## Driver contract

`fft_dma_drv` registers `/dev/fft_dma0` as a misc device. A mutex serializes access to the DMA channel and its coherent buffer.

1. Reset S2MM and clear pending DMA status.
2. Reinitialize the completion, enable completion/error interrupts, and program the coherent DMA address and 4096-byte transfer length.
3. Enable the capture source and wait up to one second for the S2MM interrupt.
4. Stop capture, reject timeout/error status, then calculate the largest complex FFT bin in the coherent buffer.
5. Copy only the result structure to user space.

The IRQ handler acknowledges the AXI DMA status before completing the waiter. This avoids leaving a level-triggered completion interrupt pending.

## User-space ABI

`FFT_DMA_IOCTL_RUN` is defined in `include/uapi/fft_dma_uapi.h`. It takes a pointer to `struct fft_dma_result` and returns zero only after a complete, error-free transfer.

| Field | Meaning |
| --- | --- |
| `dma_status` | AXI DMA S2MM status sampled after the request |
| `bytes_received` | S2MM transfer-length register reported by the design |
| `peak_bin` | Index with the largest complex magnitude |
| `peak_real`, `peak_imag` | Q15 value at `peak_bin` |
| `peak_magnitude_squared` | `real^2 + imag^2`, calculated in the driver |

The ioctl returns `-ETIMEDOUT` for a missing completion, `-EIO` for DMA error or an invalid post-completion state, and `-EOVERFLOW` if Linux provides a DMA address the 32-bit AXI DMA cannot represent. Unknown ioctl numbers return `-ENOTTY`.

## Buildroot integration

The `fft-dma-uapi` package installs the shared UAPI header into Buildroot's staging sysroot. The driver and both applications depend on that package, so the header is compiled from one source instead of copied between directories.

After modifying a local package, rebuild from the Linux-native workspace:

```bash
make -C build/buildroot-zynq7020 fft-dma-uapi-dirclean
make -C build/buildroot-zynq7020 fft-dma-driver-dirclean
make -C build/buildroot-zynq7020 fft-dma-test-dirclean
make -C build/buildroot-zynq7020 fft-ethernet-server-dirclean
make -C build/buildroot-zynq7020
```

## Target evidence and limits

The validated SD-boot result is documented in [VALIDATION.md](VALIDATION.md). It proves the kernel-driver path, including a runtime coherent DMA address and DMA completion interrupt, not an ADC acquisition pipeline or a sustained-rate benchmark. The only input source here is the deterministic PL test generator `axis_sample_sim`.
