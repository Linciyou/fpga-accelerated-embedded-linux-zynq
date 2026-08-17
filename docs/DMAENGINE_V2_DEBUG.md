# DMAengine V2 Validation and Debugging

V2 changes `fft_dma_drv` from an AXI DMA register driver into a DMAengine client. The standard Xilinx AXI DMA driver owns the S2MM register block and interrupt. `fft_dma_drv` requests the S2MM channel, allocates its coherent buffer with the DMAengine device, submits one `DMA_DEV_TO_MEM` descriptor, and waits for the completion callback.

## JTAG-first validation

Do not rebuild or write the SD image until this sequence passes.

1. Build the Vivado design and Buildroot image in the normal Linux-native workspace.
2. Run `buildroot-external/scripts/make_jtag_assets.sh` with the Buildroot images directory.
3. Copy `zImage`, `rootfs.cpio.gz`, and `zynq7020-fft-jtag.dtb` to `build/linux_images/` on Windows.
4. Run `hardware/vivado/jtag_boot_dmaengine.tcl` through XSCT. This loads the bitstream, kernel, initramfs, and DTB through JTAG only. It does not write QSPI or the SD card.
5. Configure the direct Ethernet link and run:

   ```powershell
   .\scripts\set_direct_ethernet.ps1 -InterfaceAlias "<USB Ethernet alias>"
   .\scripts\test_dmaengine_stress.ps1
   ```

The script sends `BENCH 1000` and `BENCH 10000`. Each result is valid only when `ok` matches `iterations` and `failed`, `timeouts`, `dma_errors`, and `validation_errors` are all zero.

## Benchmark definition

`fft_dma_bench` measures each `FFT_DMA_IOCTL_RUN` call on the target. A sample starts before the ioctl and ends after the DMAengine completion callback, FFT peak calculation, and copy back to user space. The report includes minimum, mean, p50, p95, and maximum latency in microseconds.

`throughput_mib_s` is successful 4096-byte frames divided by elapsed benchmark time. It measures sequential end-to-end acquisition rate. It is not a raw AXI DMA bus bandwidth or an ADC sample-rate claim.

## Test record

| Test | Command | Acceptance | Result |
| --- | --- | --- | --- |
| Smoke | `RUN` | `status=0x00000001`, `bytes=4096`, `peak=1` | Pass: `re=16384`, `im=0`, `mag2=268435456` |
| Stress | `BENCH 1000` | 1000 successful, zero errors | Pass: `ok=1000`, `failed=0`, `timeouts=0`, `dma_errors=0` |
| Stress | `BENCH 10000` | 10000 successful, zero errors | Pass: `ok=10000`, `failed=0`, `timeouts=0`, `dma_errors=0` |
| Benchmark | `BENCH 1000` and `BENCH 10000` | Capture reported latency and throughput | 1k: avg `205.119 us`, p95 `205.854 us`, `18.891 MiB/s`; 10k: avg `205.413 us`, p95 `207.378 us`, `18.863 MiB/s` |

JTAG run on 2026-08-17 used the direct Ethernet link (`192.168.7.1` to
`192.168.7.2`). The raw records were:

```text
DMAENGINE_BENCH iterations=1000 ok=1000 failed=0 timeouts=0 dma_errors=0 validation_errors=0 bytes=4096000 elapsed_us=206782 min_us=193.110 avg_us=205.119 p50_us=204.162 p95_us=205.854 max_us=313.830 throughput_mib_s=18.891
DMAENGINE_BENCH iterations=10000 ok=10000 failed=0 timeouts=0 dma_errors=0 validation_errors=0 bytes=40960000 elapsed_us=2070898 min_us=202.740 avg_us=205.413 p50_us=204.390 p95_us=207.378 max_us=316.284 throughput_mib_s=18.863
```

The JTAG gate has passed. Rebuild the software-only SD image next, then repeat
the same test after SD boot.

## SD image handoff

The software-only SD image was regenerated after the JTAG gate, written to a
non-system USB SD reader, and byte-for-byte verified for all `130023936` bytes.
Its SHA-256 is
`0fc9c461771e4b123a7d14083e0dca93dbe91391079344d2f4e6cceec3b0d4a1`.
This establishes the deployment media contents, not SD boot success. The next
record must repeat `RUN`, `BENCH 1000`, and `BENCH 10000` after booting from
the card.

## SD boot record

The validated card was inserted in the FPGA board and the system was reset into
the existing QSPI hardware boot stage. The direct Ethernet service replied to
`PING`, then the V2 payload from SD produced:

```text
RESULT status=0x00000001 bytes=4096 peak=1 re=16384 im=0 mag2=268435456
DMAENGINE_BENCH iterations=1000 ok=1000 failed=0 timeouts=0 dma_errors=0 validation_errors=0 bytes=4096000 elapsed_us=207694 min_us=203.268 avg_us=206.033 p50_us=204.288 p95_us=206.520 max_us=703.734 throughput_mib_s=18.808
DMAENGINE_BENCH iterations=10000 ok=10000 failed=0 timeouts=0 dma_errors=0 validation_errors=0 bytes=40960000 elapsed_us=2070706 min_us=202.926 avg_us=205.375 p50_us=204.450 p95_us=206.574 max_us=474.000 throughput_mib_s=18.864
```

This is the final V2 evidence: QSPI supplied the existing FSBL, bitstream, and
U-Boot; SD supplied the V2 kernel, DTB, root filesystem, DMAengine client, and
benchmark.

## Timeout record

The V2 client returns `ETIMEDOUT` after 1000 ms if its DMAengine callback does not run. It disables the capture GPIO and calls `dmaengine_terminate_sync()` before returning, so the next request starts from a terminated channel.

Capture these commands immediately after a timeout:

```sh
dmesg | tail -n 80
cat /proc/interrupts
cat /sys/kernel/debug/dmaengine/summary 2>/dev/null
```

Expected driver log:

```text
S2MM DMAengine request timed out after 1000 ms
```

Check that the XFFT stream reaches the S2MM input, `TLAST` reaches AXI DMA, the capture GPIO changes state, and the S2MM interrupt is wired to GIC SPI 29.

## IRQ or DMAengine error record

The custom driver no longer acknowledges AXI DMA status registers. The Xilinx DMAengine driver owns the IRQ and reports completion through the callback. If the callback runs but `dmaengine_tx_status()` is not `DMA_COMPLETE`, V2 returns `EIO`, terminates the channel, and logs the DMAengine status and residue.

Capture the same `dmesg`, `/proc/interrupts`, and DMAengine summary output. An interrupt counter that does not change points to the PL-to-PS IRQ path. A counter that changes with `EIO` points to a stream protocol, DMA configuration, or AXI error that must be diagnosed in the Xilinx DMAengine log.

## Device Tree error record

The DMA controller and client are separate DT nodes:

| Node | Required properties |
| --- | --- |
| `axi_dma_fft` | `xlnx,axi-dma-1.00.a`, clocks, `#dma-cells = <1>`, S2MM child, and IRQ |
| `fft_dma` | capture `reg`, `dmas = <&axi_dma_fft 1>`, and `dma-names = "rx"` |

The channel argument must be `1`: the Xilinx driver assigns S2MM to channel 1 when AXI DMA has its normal MM2S/S2MM channel slots. A missing DMA provider can produce probe deferral; a malformed client node makes `dma_request_chan()` fail.

Capture:

```sh
dmesg | grep -E 'xilinx-dma|fft-dma|dmaengine'
ls -l /sys/class/misc/fft_dma0
find /sys/firmware/devicetree/base -maxdepth 3 -type f | grep -E 'dma|fft'
```

Do not use a fixed DMA address or `/dev/mem` as a workaround. That would bypass the V2 DMAengine path being validated.
