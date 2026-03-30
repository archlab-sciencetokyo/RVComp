/* SPDX-License-Identifier: MIT */
#ifndef RVCOMP_CAM_UAPI_H
#define RVCOMP_CAM_UAPI_H

#include <stdint.h>
#include <sys/ioctl.h>

#define RVCOMP_CAM_PIXFMT_GRAY8 0x59455247u /* "GREY" */

struct rvcomp_cam_info {
	uint32_t width;
	uint32_t height;
	uint32_t stride;
	uint32_t frame_bytes;
	uint32_t pixfmt;
};

struct rvcomp_cam_meta {
	uint32_t seq;
	uint32_t ready_bank;
	uint32_t read_bank;
	uint32_t drop_count;
	uint32_t status;
};

#define RVCOMP_CAM_IOC_MAGIC  'P'
#define RVCOMP_CAM_IOC_G_INFO _IOR(RVCOMP_CAM_IOC_MAGIC, 0x00, struct rvcomp_cam_info)
#define RVCOMP_CAM_IOC_G_META _IOR(RVCOMP_CAM_IOC_MAGIC, 0x01, struct rvcomp_cam_meta)

#endif
