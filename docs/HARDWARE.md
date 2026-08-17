# Zynq-7020 FPGA Hardware

These facts were derived from the supplied v2.0 board schematic. The original
PDF is retained locally as reference material and is not committed to Git.

## Confirmed devices

- FPGA/SoC: Xilinx Zynq-7000 `XC7Z020-2CLG484I`
- DDR3: Micron `MT41K256M16TW-107:P`
- QSPI flash: Winbond `W25Q256JVEIQ`
- EEPROM: `M24C02`
- PS reference clock: 33.333 MHz
- PL reference clock: 50 MHz
- SD card: PS MIO40-MIO47
- USB-UART: CH340E connected to PS UART nets
- Ethernet PHY: Realtek `RTL8211E-VB-CG` through PL RGMII I/O

## Boot wiring

QSPI stores FSBL, the PL bitstream, and U-Boot. Linux remains on the SD card.

| Interface | Connection |
| --- | --- |
| QSPI | PS MIO1-MIO6 |
| SD clock | PS MIO40 |
| SD command | PS MIO41 |
| SD data | PS MIO42-MIO45 |
| SD card detect | PS MIO47 |
| Ethernet | PS GEM0 through EMIO, PL GMII-to-RGMII, RTL8211E PHY |

The board uses SW3-1 ON and SW3-2 OFF for QSPI boot. Boot straps are sampled at
power-on reset, so changing SW3 requires a full power cycle.

## Accelerator interfaces

The accelerator stays within the Zynq PS/PL boundary and does not require an
external PL data connector:

```text
Simulated 100 MSPS source
  -> AXI4-Stream FIFO
  -> Xilinx XFFT
  -> AXI DMA S2MM
  -> Zynq HP0
  -> PS DDR
```

Linux uses the standard Xilinx AXI DMA DMAengine driver for S2MM register and
IRQ ownership. `fft_dma_drv` is the client: it allocates a coherent 4 KiB
buffer, submits an S2MM descriptor, waits for the callback, and exposes results
through `/dev/fft_dma0`.

The synthesizable `axis_sample_sim` source produces deterministic 1024-sample
Q15 frames at a 100 MHz stream clock. It validates the complete PL-to-Linux
path before an external ADC is introduced. Replacing it with an ADC receiver
preserves the FIFO, XFFT, DMA, Device Tree, driver, and userspace interfaces.
