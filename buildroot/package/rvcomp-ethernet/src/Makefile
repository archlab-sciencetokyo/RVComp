# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 Archlab, Science Tokyo

obj-m += rvcomp_ethernet.o

KDIR ?= /lib/modules/$(shell uname -r)/build

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
