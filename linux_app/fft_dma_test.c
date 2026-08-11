/* SPDX-License-Identifier: MIT */
/* Userspace validation client for the zynq7020-fft-dma kernel driver. */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <fft_dma_uapi.h>

int main(void)
{
    struct fft_dma_result result = { };
    int fd = open("/dev/fft_dma0", O_RDWR);

    if (fd < 0) {
        fprintf(stderr, "open /dev/fft_dma0 failed: %s\n", strerror(errno));
        return 10;
    }
    if (ioctl(fd, FFT_DMA_IOCTL_RUN, &result) < 0) {
        fprintf(stderr, "FFT DMA ioctl failed: %s\n", strerror(errno));
        close(fd);
        return 11;
    }
    close(fd);

    printf("Kernel DMA FFT acquisition OK\n");
    printf("S2MM status: 0x%08x, bytes: %u\n",
           result.dma_status, result.bytes_received);
    printf("Peak bin: %u, re: %d, im: %d, mag2: %llu\n",
           result.peak_bin, result.peak_real, result.peak_imag,
           (unsigned long long)result.peak_magnitude_squared);

    if (result.bytes_received != 4096u || result.peak_bin != 1u) {
        fprintf(stderr, "Unexpected kernel DMA FFT result\n");
        return 2;
    }
    return 0;
}
