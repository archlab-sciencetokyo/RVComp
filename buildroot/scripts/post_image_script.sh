#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# Buildroot post-image hook for mmc_defconfig:
# - First pass builds minimal initramfs/fw_payload
# - Second pass builds full MMC ext4 rootfs by inheriting 1st-pass .config
#   and applying mmc-rootfs-only fragment overrides

set -eu

if [ "${RVCOMP_MMC_SECOND_PASS:-0}" = "1" ]; then
    exit 0
fi

if [ -z "${BASE_DIR:-}" ] || [ -z "${BINARIES_DIR:-}" ]; then
    echo "[rvcomp-post-image] BASE_DIR/BINARIES_DIR is not set" >&2
    exit 1
fi

if [ -z "${BR2_CONFIG:-}" ]; then
    echo "[rvcomp-post-image] BR2_CONFIG is not set" >&2
    exit 1
fi

if [ ! -f "${BR2_CONFIG}" ]; then
    echo "[rvcomp-post-image] BR2_CONFIG not found: ${BR2_CONFIG}" >&2
    exit 1
fi

BR_SRC_DIR="${PWD}"
if [ ! -f "${BR_SRC_DIR}/Makefile" ] || [ ! -f "${BR_SRC_DIR}/package/Config.in" ]; then
    echo "[rvcomp-post-image] cannot locate Buildroot source dir from PWD=${PWD}" >&2
    exit 1
fi

EXTERNAL_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ROOTFS_OUT_DIR="${BASE_DIR}/output-rootfs"
ROOTFS_IMG="${ROOTFS_OUT_DIR}/images/rootfs.ext4"
ROOTFS_CONFIG="${ROOTFS_OUT_DIR}/.config"
ROOTFS_FRAGMENT="${EXTERNAL_DIR}/configs/mmc_rootfs_second_pass.fragment"
JOBS="${PARALLEL_JOBS:-1}"

if [ ! -f "${ROOTFS_FRAGMENT}" ]; then
    echo "[rvcomp-post-image] fragment not found: ${ROOTFS_FRAGMENT}" >&2
    exit 1
fi

echo "[rvcomp-post-image] build secondary rootfs: inherit 1st-pass .config + fragment"
case "${ROOTFS_OUT_DIR}" in
    ""|"/")
        echo "[rvcomp-post-image] invalid ROOTFS_OUT_DIR: ${ROOTFS_OUT_DIR}" >&2
        exit 1
        ;;
esac

if [ -d "${ROOTFS_OUT_DIR}" ]; then
    echo "[rvcomp-post-image] clean stale second-pass output: ${ROOTFS_OUT_DIR}"
    rm -rf "${ROOTFS_OUT_DIR}"
fi

mkdir -p "${ROOTFS_OUT_DIR}"
cp "${BR2_CONFIG}" "${ROOTFS_CONFIG}"
printf '\n# rvcomp second-pass fragment overrides\n' >> "${ROOTFS_CONFIG}"
cat "${ROOTFS_FRAGMENT}" >> "${ROOTFS_CONFIG}"

env RVCOMP_MMC_SECOND_PASS=1 make -C "${BR_SRC_DIR}" \
    O="${ROOTFS_OUT_DIR}" \
    BR2_EXTERNAL="${EXTERNAL_DIR}" \
    olddefconfig

env RVCOMP_MMC_SECOND_PASS=1 make -C "${BR_SRC_DIR}" \
    O="${ROOTFS_OUT_DIR}" \
    BR2_EXTERNAL="${EXTERNAL_DIR}" \
    -j"${JOBS}"

if [ ! -f "${ROOTFS_IMG}" ]; then
    echo "[rvcomp-post-image] missing rootfs image: ${ROOTFS_IMG}" >&2
    exit 1
fi

cp "${ROOTFS_IMG}" "${BINARIES_DIR}/rootfs.ext4"
echo "[rvcomp-post-image] exported ${BINARIES_DIR}/rootfs.ext4"
