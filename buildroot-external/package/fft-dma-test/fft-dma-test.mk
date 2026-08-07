################################################################################
#
# fft-dma-test
#
################################################################################

FFT_DMA_TEST_VERSION = 1.0
FFT_DMA_TEST_SITE = $(BR2_EXTERNAL_ZYNQ7020_PATH)/../linux_app
FFT_DMA_TEST_SITE_METHOD = local
FFT_DMA_TEST_LICENSE = MIT
FFT_DMA_TEST_DEPENDENCIES = fft-dma-driver

define FFT_DMA_TEST_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -O2 -Wall -Wextra \
		$(@D)/fft_dma_test.c -o $(@D)/fft_dma_test
endef

define FFT_DMA_TEST_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/fft_dma_test $(TARGET_DIR)/usr/bin/fft_dma_test
endef

$(eval $(generic-package))
