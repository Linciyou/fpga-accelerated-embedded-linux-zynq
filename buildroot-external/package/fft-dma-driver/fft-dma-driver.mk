################################################################################
#
# fft-dma-driver
#
################################################################################

FFT_DMA_DRIVER_VERSION = 1.0
FFT_DMA_DRIVER_SITE = $(BR2_EXTERNAL_ZYNQ7020_PATH)/../linux_driver
FFT_DMA_DRIVER_SITE_METHOD = local
FFT_DMA_DRIVER_LICENSE = GPL-2.0-only
FFT_DMA_DRIVER_DEPENDENCIES = fft-dma-uapi
FFT_DMA_DRIVER_MODULE_MAKE_OPTS = KCFLAGS=-I$(STAGING_DIR)/usr/include

$(eval $(kernel-module))
$(eval $(generic-package))
