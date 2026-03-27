# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Archlab, Science Tokyo

RVCOMP_BOOTFILES_VERSION = 1.0
RVCOMP_BOOTFILES_SITE = $(BR2_EXTERNAL_RVCOMP_PATH)/package/rvcomp-bootfiles/files
RVCOMP_BOOTFILES_SITE_METHOD = local
RVCOMP_BOOTFILES_LICENSE = GPL-2.0
RVCOMP_BOOTFILES_LICENSE_FILES =

define RVCOMP_BOOTFILES_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/init $(TARGET_DIR)/init
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/etc/rvcomp/initramfs.d
	rm -f \
		$(TARGET_DIR)/etc/rvcomp/initramfs.d/S20-rvcomp-ethernet \
		$(TARGET_DIR)/etc/rvcomp/initramfs.d/S30-rvcomp-mmc-rootfs
	if [ -n "$(BR2_PACKAGE_RVCOMP_ETHERNET)" ]; then \
		$(INSTALL) -D -m 0755 $(@D)/S20-rvcomp-ethernet \
			$(TARGET_DIR)/etc/rvcomp/initramfs.d/S20-rvcomp-ethernet; \
	fi
	if [ -n "$(BR2_PACKAGE_RVCOMP_MMC)" ]; then \
		$(INSTALL) -D -m 0755 $(@D)/S30-rvcomp-mmc-rootfs \
			$(TARGET_DIR)/etc/rvcomp/initramfs.d/S30-rvcomp-mmc-rootfs; \
	fi
endef

$(eval $(generic-package))
