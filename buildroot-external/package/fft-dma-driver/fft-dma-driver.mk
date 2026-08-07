################################################################################
#
# fft-dma-driver
#
################################################################################

FFT_DMA_DRIVER_VERSION = 1.0
FFT_DMA_DRIVER_SITE = $(BR2_EXTERNAL_ZYNQ7020_PATH)/../linux_driver
FFT_DMA_DRIVER_SITE_METHOD = local
FFT_DMA_DRIVER_LICENSE = GPL-2.0-only

$(eval $(kernel-module))
$(eval $(generic-package))
