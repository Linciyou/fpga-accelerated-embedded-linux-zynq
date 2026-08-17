# V1 Direct-Register Driver

`fft_dma_v1.c` is the original working driver retained as a reference point for
the DMAengine migration. It maps the AXI DMA register block, programs the S2MM
destination address and transfer length directly, and completes the ioctl from
its own IRQ handler.

It is intentionally not included in the Buildroot package and must not be
built alongside V2. The V1 Device Tree contract was
`bghjn,zynq7020-fft-dma-1.0`, with named `dma` and `capture` resources plus the
S2MM interrupt. The current image uses the V2 DMAengine client in
`../fft_dma_drv.c`.

The source is preserved so the ownership change can be reviewed in one tree;
the V1 SD-boot result remains documented in
[`docs/VALIDATION.md`](../../docs/VALIDATION.md).
