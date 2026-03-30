# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2025 Archlab, Science Tokyo

define OPENSBI_COMPLETE_BUILD_CHAIN
	@echo "Ensuring complete build chain: rootfs.cpio -> linux -> opensbi"
	if [ ! -f $(@D)/.stamp_linux_built_once ]; then \
              touch $(@D)/.stamp_linux_built_once; \
              $(MAKE) linux; \
        fi
endef

OPENSBI_PRE_BUILD_HOOKS += OPENSBI_COMPLETE_BUILD_CHAIN

define OPENSBI_REBUILD_AFTER_BUILD
	if [ ! -f $(@D)/.stamp_opensbi_rebuilt_once ]; then \
		echo "HOOK ==> Rebuilding opensbi..."; \
		touch $(@D)/.stamp_opensbi_rebuilt_once; \
                $(MAKE) linux-rebuild-with-initramfs; \
		$(MAKE) opensbi-rebuild; \
	fi
endef

OPENSBI_POST_BUILD_HOOKS += OPENSBI_REBUILD_AFTER_BUILD

include $(sort $(wildcard $(BR2_EXTERNAL_RVCOMP_PATH)/package/*/*.mk))
