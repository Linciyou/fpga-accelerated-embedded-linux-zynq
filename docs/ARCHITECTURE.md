# FPGA and Embedded Linux Architecture

## Boot storage

QSPI holds FSBL, the PL bitstream, and U-Boot. The `qspi-boot` MTD partition
is 6 MiB. The SD card holds `uImage`, `zynq7020-fft.dtb`, `extlinux.conf`, and
the ext4 root filesystem.

```text
BootROM -> FSBL -> bitstream -> U-Boot -> SD kernel/DTB -> SD rootfs
```

Set SW3-1 ON and SW3-2 OFF for QSPI boot. The strap pins are sampled during
power-on reset.

## Workload and DMA path

```text
axis_sample_sim -> AXI4-Stream FIFO -> Xilinx XFFT IP -> AXI DMA S2MM
  -> HP0 -> Xilinx AXI DMAengine driver -> coherent buffer
  -> fft_dma_drv DMAengine client -> ioctl client
```

The Xilinx XFFT IP is the workload used to exercise the stream and is not custom
FFT RTL. The Device Tree describes the AXI DMA provider, then gives
`fft_dma_drv` the capture GPIO and S2MM DMA channel. The client allocates one
`FFT_DMA_FRAME_BYTES` coherent buffer, submits one descriptor, and waits up to
`FFT_DMA_TIMEOUT_MS` for the completion callback. The ioctl returns the
completion status, received bytes, and peak sample. The full Linux contract is
in [LINUX_INTEGRATION.md](LINUX_INTEGRATION.md).

## Ethernet control

`fft_ethernet_server` listens on TCP port 5000. `PING` returns `PONG`; `RUN`
opens `/dev/fft_dma0` and calls `FFT_DMA_IOCTL_RUN`. Ethernet is only used to
start a test and read its result.

## Replacing the sample source

`axis_sample_sim` is a synthesizable test source. An ADC receiver can replace
it without changing the FIFO, XFFT, AXI DMA, Device Tree, driver, or userspace
interface.
