################################################################################
#
# fft-dma-bench
#
################################################################################

FFT_DMA_BENCH_VERSION = 2.0
FFT_DMA_BENCH_SITE = $(BR2_EXTERNAL_ZYNQ7020_PATH)/../linux_app
FFT_DMA_BENCH_SITE_METHOD = local
FFT_DMA_BENCH_LICENSE = MIT
FFT_DMA_BENCH_DEPENDENCIES = fft-dma-driver fft-dma-uapi

define FFT_DMA_BENCH_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -O2 -Wall -Wextra \
		-I$(STAGING_DIR)/usr/include \
		$(@D)/fft_dma_bench.c -o $(@D)/fft_dma_bench
endef

define FFT_DMA_BENCH_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/fft_dma_bench \
		$(TARGET_DIR)/usr/bin/fft_dma_bench
endef

$(eval $(generic-package))
