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

## DMA path

```text
axis_sample_sim -> AXI4-Stream FIFO -> XFFT -> AXI DMA S2MM
  -> HP0 -> coherent buffer -> fft_dma_drv -> ioctl client
```

The Device Tree gives `fft_dma_drv` a DMA register range, a capture GPIO range,
and the S2MM interrupt. The driver allocates a 4 KiB coherent buffer, resets
and starts S2MM, writes the DMA address and length, then waits up to one second
for the interrupt. The ioctl returns DMA status, received bytes, and the peak
sample. The full Linux contract is in [LINUX_INTEGRATION.md](LINUX_INTEGRATION.md).

## Ethernet control

`fft_ethernet_server` listens on TCP port 5000. `PING` returns `PONG`; `RUN`
opens `/dev/fft_dma0` and calls `FFT_DMA_IOCTL_RUN`. Ethernet is only used to
start a test and read its result.

## Replacing the sample source

`axis_sample_sim` is a synthesizable test source. An ADC receiver can replace
it without changing the FIFO, XFFT, AXI DMA, Device Tree, driver, or userspace
interface.
