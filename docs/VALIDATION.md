# FPGA and Embedded Linux Validation

## V1 baseline

The values below were captured by the V1 register-level driver before the
DMAengine V2 conversion. They are retained as a hardware baseline, not as V2
results.

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

## DMAengine V2

V2 passed JTAG boot on 2026-08-17 over the direct Ethernet link. `RUN` returned
`status=0x00000001 bytes=4096 peak=1`, `BENCH 1000` completed with zero errors
at `18.891 MiB/s`, and `BENCH 10000` completed with zero errors at
`18.863 MiB/s`. The full latency distribution and debugging records are in
[DMAENGINE_V2_DEBUG.md](DMAENGINE_V2_DEBUG.md).

The V2 software-only SD image has been regenerated from this tested payload.
On 2026-08-17 it was written to a non-system 15.9 GB USB SD reader as `Disk 1`
and a byte-for-byte verification passed for all `130023936` image bytes. The
image SHA-256 is
`0fc9c461771e4b123a7d14083e0dca93dbe91391079344d2f4e6cceec3b0d4a1`.

The card was then booted in the FPGA board. `RUN` returned
`status=0x00000001 bytes=4096 peak=1`; `BENCH 1000` completed with zero errors
at `18.808 MiB/s`; and `BENCH 10000` completed with zero errors at
`18.864 MiB/s`. This validates the QSPI hardware boot stage followed by the V2
software payload from SD.
