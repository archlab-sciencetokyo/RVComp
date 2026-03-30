# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Archlab, Science Tokyo

RVCOMP_CAMERA_VERSION = 1.0
RVCOMP_CAMERA_SITE = $(BR2_EXTERNAL_RVCOMP_PATH)/package/rvcomp-camera/src
RVCOMP_CAMERA_SITE_METHOD = local
RVCOMP_CAMERA_LICENSE = GPL-2.0
RVCOMP_CAMERA_LICENSE_FILES =

$(eval $(kernel-module))
$(eval $(generic-package))
