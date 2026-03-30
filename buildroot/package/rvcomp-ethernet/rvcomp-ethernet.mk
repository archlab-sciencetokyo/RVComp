# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Archlab, Science Tokyo

RVCOMP_ETHERNET_VERSION = 1.0
RVCOMP_ETHERNET_SITE = $(BR2_EXTERNAL_RVCOMP_PATH)/package/rvcomp-ethernet/src
RVCOMP_ETHERNET_SITE_METHOD = local
RVCOMP_ETHERNET_LICENSE = GPL-2.0
RVCOMP_ETHERNET_LICENSE_FILES =

$(eval $(kernel-module))
$(eval $(generic-package))
