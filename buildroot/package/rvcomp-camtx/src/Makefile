# SPDX-License-Identifier: MIT

CC ?= cc
CFLAGS ?= -O2
LDFLAGS ?=

all: cam_tx

cam_tx: FORCE
cam_tx: cam_tx.c rvcomp_cam_uapi.h
	$(CC) $(CFLAGS) -o $@ cam_tx.c $(LDFLAGS)

clean:
	rm -f cam_tx

FORCE:

.PHONY: all clean FORCE
