// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Archlab, Science Tokyo

#include <arpa/inet.h>
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>

#include "rvcomp_cam_uapi.h"

#define UDP_MAGIC 0x52564350u /* "RVCP" */
#define UDP_VERSION 1u
#define DEFAULT_DEV "/dev/rvcomp_cam0"
#define DEFAULT_HOST "192.168.0.2"
#define DEFAULT_PORT 5000
#define DEFAULT_PAYLOAD 1200u

struct __attribute__((packed)) rvudp_hdr {
	uint32_t magic;
	uint8_t version;
	uint8_t reserved0;
	uint16_t header_bytes;
	uint32_t seq;
	uint16_t width;
	uint16_t height;
	uint16_t chunk_idx;
	uint16_t chunk_count;
	uint16_t payload_len;
	uint16_t reserved1;
};

static volatile sig_atomic_t g_stop = 0;

static void on_signal(int sig)
{
	(void)sig;
	g_stop = 1;
}

static void print_usage(const char *prog)
{
	fprintf(stderr,
		"Usage: %s [--dev PATH] [--host IP] [--port N] [--payload N]\n"
		"Defaults: --dev %s --host %s --port %d --payload %u\n",
		prog, DEFAULT_DEV, DEFAULT_HOST, DEFAULT_PORT, DEFAULT_PAYLOAD);
}

int main(int argc, char **argv)
{
	const char *dev_path = DEFAULT_DEV;
	const char *host = DEFAULT_HOST;
	int port = DEFAULT_PORT;
	unsigned int payload = DEFAULT_PAYLOAD;
	int cam_fd = -1;
	int udp_fd = -1;
	struct sockaddr_in dst;
	struct rvcomp_cam_info info;
	struct rvcomp_cam_meta meta;
	uint8_t *frame = NULL;
	uint8_t *packet = NULL;
	size_t packet_cap;
	int i;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--dev") == 0 && i + 1 < argc) {
			dev_path = argv[++i];
		} else if (strcmp(argv[i], "--host") == 0 && i + 1 < argc) {
			host = argv[++i];
		} else if (strcmp(argv[i], "--port") == 0 && i + 1 < argc) {
			port = atoi(argv[++i]);
		} else if (strcmp(argv[i], "--payload") == 0 && i + 1 < argc) {
			payload = (unsigned int)atoi(argv[++i]);
		} else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
			print_usage(argv[0]);
			return 0;
		} else {
			print_usage(argv[0]);
			return 1;
		}
	}

	if (port <= 0 || port > 65535 || payload == 0 || payload > 1400) {
		fprintf(stderr, "Invalid --port or --payload\n");
		return 1;
	}

	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);

	cam_fd = open(dev_path, O_RDONLY);
	if (cam_fd < 0) {
		perror("open camera");
		return 1;
	}

	if (ioctl(cam_fd, RVCOMP_CAM_IOC_G_INFO, &info) < 0) {
		perror("ioctl(RVCOMP_CAM_IOC_G_INFO)");
		close(cam_fd);
		return 1;
	}

	if (info.frame_bytes == 0) {
		fprintf(stderr, "invalid frame_bytes=0\n");
		close(cam_fd);
		return 1;
	}

	frame = (uint8_t *)malloc(info.frame_bytes);
	if (!frame) {
		perror("malloc frame");
		close(cam_fd);
		return 1;
	}

	packet_cap = sizeof(struct rvudp_hdr) + payload;
	packet = (uint8_t *)malloc(packet_cap);
	if (!packet) {
		perror("malloc packet");
		free(frame);
		close(cam_fd);
		return 1;
	}

	udp_fd = socket(AF_INET, SOCK_DGRAM, 0);
	if (udp_fd < 0) {
		perror("socket");
		free(packet);
		free(frame);
		close(cam_fd);
		return 1;
	}

	memset(&dst, 0, sizeof(dst));
	dst.sin_family = AF_INET;
	dst.sin_port = htons((uint16_t)port);
	if (inet_pton(AF_INET, host, &dst.sin_addr) != 1) {
		fprintf(stderr, "invalid host IP: %s\n", host);
		close(udp_fd);
		free(packet);
		free(frame);
		close(cam_fd);
		return 1;
	}

	fprintf(stderr,
		"cam_tx: dev=%s %ux%u stride=%u frame_bytes=%u host=%s:%d payload=%u\n",
		dev_path, info.width, info.height, info.stride, info.frame_bytes,
		host, port, payload);

	while (!g_stop) {
		ssize_t r;
		uint32_t seq;
		uint32_t chunk_count;
		uint32_t offset;
		uint32_t chunk_idx;

		r = read(cam_fd, frame, info.frame_bytes);
		if (r < 0) {
			if (errno == EINTR)
				continue;
			perror("read(/dev/rvcomp_cam0)");
			break;
		}
		if ((uint32_t)r != info.frame_bytes) {
			fprintf(stderr, "short read: %zd (expected %u)\n", r, info.frame_bytes);
			continue;
		}

		if (ioctl(cam_fd, RVCOMP_CAM_IOC_G_META, &meta) == 0)
			seq = meta.seq;
		else
			seq = 0;

		chunk_count = (info.frame_bytes + payload - 1) / payload;
		offset = 0;
		for (chunk_idx = 0; chunk_idx < chunk_count; chunk_idx++) {
			struct rvudp_hdr hdr;
			uint32_t remain = info.frame_bytes - offset;
			uint16_t chunk_len = (uint16_t)((remain > payload) ? payload : remain);
			ssize_t sent;

			hdr.magic = htonl(UDP_MAGIC);
			hdr.version = UDP_VERSION;
			hdr.reserved0 = 0;
			hdr.header_bytes = htons((uint16_t)sizeof(struct rvudp_hdr));
			hdr.seq = htonl(seq);
			hdr.width = htons((uint16_t)info.width);
			hdr.height = htons((uint16_t)info.height);
			hdr.chunk_idx = htons((uint16_t)chunk_idx);
			hdr.chunk_count = htons((uint16_t)chunk_count);
			hdr.payload_len = htons(chunk_len);
			hdr.reserved1 = 0;

			memcpy(packet, &hdr, sizeof(hdr));
			memcpy(packet + sizeof(hdr), frame + offset, chunk_len);

			sent = sendto(udp_fd, packet, sizeof(hdr) + chunk_len, 0,
				      (struct sockaddr *)&dst, sizeof(dst));
			if (sent < 0) {
				perror("sendto");
				g_stop = 1;
				break;
			}

			offset += chunk_len;
		}
	}

	if (udp_fd >= 0)
		close(udp_fd);
	free(packet);
	free(frame);
	close(cam_fd);
	return 0;
}
