# Zynq-7020 FPGA + Embedded Linux FFT Accelerator

This project runs a PL FFT capture path on a Zynq-7020 board and controls it
from Buildroot Linux. `axis_sample_sim` produces a 1024-sample stream, which
passes through XFFT and AXI DMA S2MM into PS DDR.

The Linux platform driver owns the DMA channel. It allocates a 4 KiB coherent
buffer, starts the transfer, waits for the PL interrupt, and returns the FFT
peak through `/dev/fft_dma0`. User space does not map AXI DMA registers or DDR
through `/dev/mem`.

FSBL, the PL bitstream, and U-Boot boot from QSPI. The kernel, DTB, and
Buildroot root filesystem are loaded from SD.

## Linux implementation

- The Device Tree describes the DMA registers, capture GPIO, and S2MM IRQ.
- `fft_dma_drv` is a platform driver with coherent DMA memory, interrupt
  completion, request serialization, timeout handling, and a misc-device ioctl.
- `include/uapi/fft_dma_uapi.h` is the shared ABI used by the driver and both
  user-space clients.
- Buildroot builds the module, local test client, and direct Ethernet endpoint
  into the target image.

[Linux integration](docs/LINUX_INTEGRATION.md) documents the Device Tree,
driver, UAPI, and Buildroot interfaces. [Build and deploy](docs/BUILD_AND_DEPLOY.md)
contains the build and programming commands.

## Data path

```mermaid
flowchart LR
    subgraph PL["PL"]
        Source["Sample source"] --> FIFO["AXI4-Stream FIFO"]
        FIFO --> FFT["XFFT"]
        FFT --> DMA["AXI DMA S2MM"]
    end
    subgraph PS["PS and Embedded Linux"]
        Buffer["Coherent DMA buffer<br/>in PS DDR"] --> Driver["fft_dma_drv"]
        Driver --> App["fft_dma_test<br/>or Ethernet server"]
    end
    DMA --> Buffer
```

The sample source is a synthesizable test generator, not an ADC. It sends a
deterministic Q15 frame at a 100 MHz stream clock. XFFT output is bit-reversed,
so this test expects the largest value at bin 1.

## Boot layout

| Storage | Contents |
| --- | --- |
| QSPI | FSBL, PL bitstream, and U-Boot |
| SD FAT partition | `uImage`, `zynq7020-fft.dtb`, and `extlinux.conf` |
| SD ext4 partition | Buildroot root filesystem |

```text
Power on -> QSPI BootROM -> FSBL + bitstream -> U-Boot
         -> kernel + DTB from SD -> rootfs from /dev/mmcblk0p2
```

The SD image is software-only. It does not contain `BOOT.BIN`, an FSBL, a
bitstream, or U-Boot.

## Board test

After a QSPI reset and SD Linux boot, the PC sent `RUN` to the board over the
direct Ethernet link. The server opened `/dev/fft_dma0` and issued the ioctl.

```text
RESULT status=0x00000002 bytes=4096 peak=1 re=16384 im=0 mag2=268435456
```

`0x00000002` is the AXI DMA idle state after completion. The full board record,
including the dynamic coherent DMA address observed during JTAG inspection, is
in [VALIDATION.md](docs/VALIDATION.md).

## Run the direct Ethernet test

Use a direct link between the PC USB Ethernet adapter and the board. No router,
gateway, or DHCP server is used.

```text
PC:    192.168.7.1/24
Board: 192.168.7.2/24
```

```powershell
.\scripts\set_direct_ethernet.ps1 -InterfaceAlias "<USB Ethernet alias>"
.\scripts\test_fft_over_ethernet.ps1
```

## Repository layout

| Path | Contents |
| --- | --- |
| [`hardware/`](hardware) | RTL, Vivado Tcl, constraints, QSPI, and JTAG scripts |
| [`linux_driver/`](linux_driver) | AXI DMA platform driver |
| [`include/uapi/`](include/uapi) | Shared ioctl ABI |
| [`linux_app/`](linux_app) | Local test client and Ethernet server |
| [`buildroot-external/`](buildroot-external) | Buildroot defconfig, packages, DTB, and SD image files |
| [`docs/HARDWARE.md`](docs/HARDWARE.md) | Board wiring used by this design |
| [`docs/LINUX_INTEGRATION.md`](docs/LINUX_INTEGRATION.md) | Device Tree, driver, UAPI, and Buildroot details |
| [`docs/VALIDATION.md`](docs/VALIDATION.md) | Board test record and test limits |

## Development checks

Run the lightweight source checks from WSL or another Linux host:

```bash
./scripts/check_project.sh
```

This checks shell syntax and builds the user-space clients. It does not replace
the target DMA test. GitHub Actions runs the same check on pushes and pull
requests.

## Limits

- No external ADC has been connected to this design.
- Sustained-rate capture, analog signal quality, and long-duration DMA stress
  have not been measured.
- The kernel module is GPL-2.0-only because it uses GPL-only kernel symbols.
