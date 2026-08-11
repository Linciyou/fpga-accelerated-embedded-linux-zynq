# FPGA and Embedded Linux Validation

## Results

| Check | Value |
| --- | --- |
| QSPI write | `QSPI_PROGRAM_STATUS: 0x51535031` |
| Boot mode | `BOOT_MODE: 0x00000001` |
| CPU after reset | `PC: 0xC0121D28` |
| DMA destination | `DMA_S2MM_DA: 0x1F042000` |
| DMA length | `DMA_S2MM_LEN: 0x00001000` |
| DMA status | `DMA_S2MM_DMASR: 0x00000002` |
| FFT output | `peak=1 re=16384 im=0` |
| Ethernet test | Three `RUN` requests returned the expected result |

## Test sequence

1. Set SW3-1 ON and SW3-2 OFF.
2. Insert the software-only SD card and power-cycle the board.
3. Set the PC USB Ethernet adapter to `192.168.7.1/24`.
4. Run `scripts/test_fft_over_ethernet.ps1`.

Expected reply:

```text
RESULT status=0x00000002 bytes=4096 peak=1 re=16384 im=0 mag2=268435456
```

Not covered by these tests: an external ADC, sustained-rate capture, analog
signal quality, and long-duration DMA stress.

The dynamic DMA address and `/dev/fft_dma0` ioctl path demonstrate that Linux
allocated and controlled the transfer. They do not establish a fixed DDR
address or replace a throughput benchmark.
