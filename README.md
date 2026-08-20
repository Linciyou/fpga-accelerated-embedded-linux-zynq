# Zynq-7020 FPGA + Embedded Linux DMA Path

This repository contains the hardware and software for a Zynq-7020 PL-to-PS
capture path. The PL produces a fixed AXI4-Stream frame, sends it through
Xilinx XFFT and AXI DMA S2MM, and writes the result into PS DDR through HP0.
Buildroot Linux exposes one capture through `/dev/fft_dma0` and a small
Ethernet test endpoint.

XFFT is Xilinx IP used as a realistic stream workload. The FFT algorithm and
RTL are not custom work in this repository. The work here is the PS/PL
integration, DMA path, Device Tree binding, Linux client driver, Buildroot
image, and board validation.

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
[`docs/DMAENGINE_DEBUG.md`](docs/DMAENGINE_DEBUG.md).

## Boot and Ethernet test

QSPI contains the existing FSBL, PL bitstream, and U-Boot. The SD card is
software-only: kernel, DTB, Buildroot root filesystem, module, and test tools.

```text
QSPI BootROM -> FSBL + PL bitstream -> U-Boot
             -> SD kernel + DTB -> SD rootfs -> /dev/fft_dma0
```

The production image starts `fft_ethernet_server`, a TCP endpoint on port 5000.
It opens `/dev/fft_dma0` only when it receives a request, so the network path
does not own DMA registers, IRQs, or buffer addresses.

At boot, `eth0` first requests a DHCP lease. When connected to a router, or to
a PC adapter using Internet Connection Sharing, the lease supplies the board
address, default gateway, and DNS settings. The board can then access the
Internet through that Ethernet link.

When no DHCP service is present, it falls back to the original point-to-point
address. This keeps the isolated PC-to-board DMA test available without a
router or Internet connection.

```text
Router or PC Internet Connection Sharing
                  |
                  | DHCP, gateway, DNS
                  v
Zynq PS GEM0 / eth0 --> fft_ethernet_server:5000

No DHCP service:
PC USB Ethernet adapter (192.168.7.1/24)
                  |
                  | direct Ethernet cable
                  v
Zynq eth0 (192.168.7.2/24) --> fft_ethernet_server:5000
```

For the direct-link fallback mode, configure the PC adapter, then run a target
smoke test:

```powershell
.\scripts\set_direct_ethernet.ps1 -InterfaceAlias "<USB Ethernet alias>"
.\scripts\test_fft_over_ethernet.ps1
```

The endpoint accepts four text commands:

| Command | Result |
| --- | --- |
| `PING` | Returns `PONG` to confirm network reachability. |
| `RUN` | Runs one DMA-backed FFT frame and returns the completion and peak result. |
| `BENCH <iterations>` | Runs the target benchmark, for example `BENCH 10000`. |
| `NETCHECK` | Verifies target IP reachability and DNS resolution before returning `NET status=ok`. |

Use the stress script after the smoke test:

```powershell
.\scripts\test_dmaengine_stress.ps1
```

For a direct PC-to-board cable, configure the PC as the NAT gateway at
`192.168.7.1`. The target fallback uses `192.168.7.2`, gateway
`192.168.7.1`, and DNS `1.1.1.1`. Verify both the DMA service and target
Internet access:

```powershell
.\scripts\test_fft_over_ethernet.ps1 -VerifyInternet
```

The scripts communicate with the board over Ethernet. The data path being
validated remains inside the Zynq: PL stream to AXI DMA, DDR, DMAengine client,
and `/dev/fft_dma0`.

For Internet mode, connect the board to a DHCP-enabled router, or enable
Windows Internet Connection Sharing on the PC's Internet-facing adapter and
share it with the USB Ethernet adapter. The board address is assigned by DHCP;
use the router or Windows lease list to find it before sending TCP commands.
After login, verify the address, route, and name resolution on the board:

```sh
ip addr show eth0
ip route
ping -c 3 1.1.1.1
nslookup example.com
```

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
| [`linux_driver/`](linux_driver) | DMAengine client driver |
| [`include/uapi/`](include/uapi) | Shared ioctl and frame configuration |
| [`linux_app/`](linux_app) | Smoke test, benchmark, and Ethernet server |
| [`buildroot-external/`](buildroot-external) | Buildroot packages, DTB, and image scripts |
| [`docs/`](docs) | Integration notes, debug records, and validation evidence |
| [`scripts/`](scripts) | SD card, direct Ethernet, and target test helpers |

## Development check

```bash
./scripts/check_project.sh
```

This checks shell syntax, whitespace, and host compilation of the user-space
clients. It does not replace target DMA validation.

Build and deployment steps are in
[`docs/BUILD_AND_DEPLOY.md`](docs/BUILD_AND_DEPLOY.md).
