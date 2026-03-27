# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Archlab, Science Tokyo

RVCOMP_MMC_VERSION = 1.0
RVCOMP_MMC_SITE = $(BR2_EXTERNAL_RVCOMP_PATH)/package/rvcomp-mmc/src
RVCOMP_MMC_SITE_METHOD = local
RVCOMP_MMC_LICENSE = GPL-2.0
RVCOMP_MMC_LICENSE_FILES =

$(eval $(kernel-module))
$(eval $(generic-package))
