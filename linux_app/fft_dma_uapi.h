#ifndef FFT_DMA_UAPI_H
#define FFT_DMA_UAPI_H

#include <linux/ioctl.h>
#include <linux/types.h>

struct fft_dma_result {
    __u32 dma_status;
    __u32 bytes_received;
    __u32 peak_bin;
    __s16 peak_real;
    __s16 peak_imag;
    __u64 peak_magnitude_squared;
};

#define FFT_DMA_IOCTL_RUN _IOR('F', 0x01, struct fft_dma_result)

#endif
