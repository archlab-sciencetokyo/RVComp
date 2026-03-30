# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Archlab, Science Tokyo

RVCOMP_CAMTX_VERSION = 1.0
RVCOMP_CAMTX_SITE = $(BR2_EXTERNAL_RVCOMP_PATH)/package/rvcomp-camtx/src
RVCOMP_CAMTX_SITE_METHOD = local
RVCOMP_CAMTX_LICENSE = MIT
RVCOMP_CAMTX_LICENSE_FILES =

define RVCOMP_CAMTX_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) \
		CC="$(TARGET_CC)" \
		CFLAGS="$(TARGET_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)"
endef

define RVCOMP_CAMTX_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/cam_tx $(TARGET_DIR)/usr/bin/cam_tx
endef

$(eval $(generic-package))
