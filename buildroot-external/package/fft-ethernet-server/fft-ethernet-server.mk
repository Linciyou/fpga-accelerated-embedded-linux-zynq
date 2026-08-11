################################################################################
#
# fft-ethernet-server
#
################################################################################

FFT_ETHERNET_SERVER_VERSION = 1.0
FFT_ETHERNET_SERVER_SITE = $(BR2_EXTERNAL_ZYNQ7020_PATH)/../linux_app
FFT_ETHERNET_SERVER_SITE_METHOD = local
FFT_ETHERNET_SERVER_LICENSE = MIT
FFT_ETHERNET_SERVER_DEPENDENCIES = fft-dma-driver fft-dma-uapi

define FFT_ETHERNET_SERVER_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -O2 -Wall -Wextra \
		-I$(STAGING_DIR)/usr/include \
		$(@D)/fft_ethernet_server.c -o $(@D)/fft_ethernet_server
endef

define FFT_ETHERNET_SERVER_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/fft_ethernet_server \
		$(TARGET_DIR)/usr/sbin/fft_ethernet_server
endef

$(eval $(generic-package))
