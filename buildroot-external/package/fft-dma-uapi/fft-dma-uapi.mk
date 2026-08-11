################################################################################
#
# fft-dma-uapi
#
################################################################################

FFT_DMA_UAPI_VERSION = 1.0
FFT_DMA_UAPI_SITE = $(BR2_EXTERNAL_ZYNQ7020_PATH)/../include/uapi
FFT_DMA_UAPI_SITE_METHOD = local
FFT_DMA_UAPI_LICENSE = GPL-2.0 WITH Linux-syscall-note
FFT_DMA_UAPI_INSTALL_STAGING = YES

define FFT_DMA_UAPI_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0644 $(@D)/fft_dma_uapi.h \
		$(STAGING_DIR)/usr/include/fft_dma_uapi.h
endef

$(eval $(generic-package))
