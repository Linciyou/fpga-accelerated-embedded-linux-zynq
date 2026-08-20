# FPGA and Embedded Linux Validation

## Test sequence

1. Set SW3-1 ON and SW3-2 OFF.
2. Insert the software-only SD card and power-cycle the board.
3. Set the PC USB Ethernet adapter to `192.168.7.1/24`.
4. Run `scripts/test_fft_over_ethernet.ps1`.

Expected reply:

```text
RESULT status=0x00000001 bytes=4096 peak=1 re=16384 im=0 mag2=268435456
```

Not covered by these tests: an external ADC, sustained-rate capture, analog
signal quality, and multi-hour reliability.

The dynamic DMA address and `/dev/fft_dma0` ioctl path demonstrate that Linux
allocated and controlled the transfer. They do not establish a fixed DDR
address or replace a throughput benchmark.

## DMAengine validation

The DMAengine implementation passed JTAG boot on 2026-08-17 over the direct
Ethernet link. `RUN` returned
`status=0x00000001 bytes=4096 peak=1`, `BENCH 1000` completed with zero errors
at `18.891 MiB/s`, and `BENCH 10000` completed with zero errors at
`18.863 MiB/s`. The full latency distribution and debugging records are in
[DMAENGINE_DEBUG.md](DMAENGINE_DEBUG.md).

The software-only SD image was regenerated from this tested payload.
On 2026-08-17 it was written to a non-system 15.9 GB USB SD reader as `Disk 1`
and a byte-for-byte verification passed for all `130023936` image bytes. The
image SHA-256 is
`0fc9c461771e4b123a7d14083e0dca93dbe91391079344d2f4e6cceec3b0d4a1`.

The card was then booted in the FPGA board. `RUN` returned
`status=0x00000001 bytes=4096 peak=1`; `BENCH 1000` completed with zero errors
at `18.808 MiB/s`; and `BENCH 10000` completed with zero errors at
`18.864 MiB/s`. This validates the QSPI hardware boot stage followed by the
software payload from SD.
