# RVComp

## Document
If you want to read the document, please visit the [RVComp Documentation Pages](https://archlab-sciencetokyo.github.io/RVComp-doc/).

[Demo](https://archlab-sciencetokyo.github.io/RVComp-doc/intro/demo.html) is here.

## Overview
RVComp is a RISC-V SoC (System on Chip) with a five-stage pipeline. It supports the RV32IMASU_Zicntr_Zicsr_Zifencei instruction set, including privileged modes and the Sv32 virtual memory system, so it can run Linux. The RVComp project began in June 2024 and offers the following characteristics:

- **High operating frequency**: Achieves a maximum clock frequency of **170 MHz** (Version 1.0.0) on a Nexys A7-100T (XC7A100T-1CSG324C)
- **HDL implementation**: RVComp is described in Verilog HDL with a from-scratch design except for the DRAM controller and clock generation
- **Permissive licensing**: All HDL components except IP are provided under the MIT license


- **Ethernet support**: 100 Mbps Ethernet controller with RMII (Nexys 4 DDR) and MII (Arty A7) interfaces, including hardware MAC filtering and FCS computation
- **microSD boot support**: microSD controller enabling Linux to boot and operate from a microSD card on the Nexys 4 DDR board
- **Interactive configuration**: Various SoC parameters can be configured through a terminal-based GUI (`tools/setting.py`)
- **Docker support**: Containerized build environment with simulation tools pre-installed (Vivado must be installed natively)


## LICENSE

RVComp files we developed from scratch are distributed under the [MIT license](https://opensource.org/licenses/MIT).



However, please note that the RVComp project uses multiple open-source components.
The following components follow their respective licenses; see the LICENSE file for full details.

- **DRAM controller**: [Xilinx MIG](https://www.amd.com/en/products/adaptive-socs-and-fpgas/intellectual-property/mig.html#documentation) ([Xilinx End User License Agreement](https://account.amd.com/content/dam/account/en/licenses/download/end-user-license-agreement.pdf))
- **Clock generation**: Xilinx Clocking Wizard ([Xilinx End User License Agreement](https://account.amd.com/content/dam/account/en/licenses/download/end-user-license-agreement.pdf))
- **prog/coremark**: [CoreMark](https://github.com/eembc/coremark) ([COREMARK® ACCEPTABLE USE AGREEMENT + Apache License 2.0](https://github.com/eembc/coremark?tab=License-1-ov-file))
- **prog/embench**: [Embench-IoT](https://github.com/embench/embench-iot) ([GPL-3.0 License](https://github.com/embench/embench-iot?tab=GPL-3.0-1-ov-file))
- **prog/riscv-tests**: [riscv-tests](https://github.com/riscv/riscv-tests) ([The Regents of the University of California (Regents)](https://github.com/riscv-software-src/riscv-tests?tab=License-1-ov-file))
- **OpenSBI**: [OpenSBI customized for RVComp](https://github.com/archlab-sciencetokyo/opensbi.git) ([BSD-2-Clause License](https://github.com/archlab-sciencetokyo/opensbi?tab=License-1-ov-file))


- **buildroot**: Device drivers, configuration files, and patches to build Linux ([GPL-2.0 License](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)).
- **RVComp-buildenv**: Build scripts that use Buildroot to produce Linux images ([GPL-2.0 License](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)). Prebuilt Linux images also include third-party software such as Linux and OpenSBI, so redistribution must follow the licenses of those components.
- **tools/XilinxBoardStore**: [Xilinx Board Store](https://github.com/Xilinx/XilinxBoardStore) ([Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0))

## Supported instruction sets

- **Base ISA**: RV32I (integer)
- **Extensions**:
  - M extension: multiplication and division instructions
  - A extension: atomic instructions (LR/SC and AMO)
  - S extension: supervisor mode
  - U extension: user mode
  - Zicntr: counter access instructions
  - Zicsr: CSR access instructions
  - Zifencei: instruction-fetch fences
- **Virtual memory**: Sv32 (two-level page tables with 4 KB pages)

# Demo

A camera streaming demo running on RVComp. Source code is available in the [`feature/v1.1.0-demo`](https://github.com/archlab-sciencetokyo/RVComp/tree/feature/v1.1.0-demo) branch of the [RVComp](https://github.com/archlab-sciencetokyo/RVComp) repository.

## Overview

This demo uses an [OV7670 (OmniVision)](https://www.ovt.com/press-releases/omnivision-launches-seventh-generation-vga-camerachip-for-mobile-applications/) camera module connected to a Nexys 4 DDR board. The camera captures 320×240 frames, converts them to 8-bit grayscale on the FPGA, and transmits them to a host PC over Ethernet. The demo runs on a local network (LAN).

```
OV7670 → FPGA (Gray8 capture) → Linux (cam_tx, UDP) → Host (relay.py, WebSocket) → Browser
```

## Demo Video

The demo is filmed in a bright indoor environment. Because frames are encoded as 8-bit grayscale, good ambient lighting improves image quality.

```{raw} html
<video width="100%" controls>
  <source src="../_static/media/demo.mp4" type="video/mp4">
</video>
```

## Running the Demo

### On RVComp (Linux)

After booting Linux, assign an IP address and bring up the Ethernet interface:

```sh
$ ip addr add <IP_ADDRESS>/<PREFIX_LEN> dev eth0
$ ip link set eth0 up
```

Then start the camera transmitter:

```sh
$ cam_tx --host <HOST_IP_ADDRESS>
```

```
Usage: cam_tx [--dev PATH] [--host IP] [--port N] [--payload N]
Defaults: --dev /dev/rvcomp_cam0 --host 192.168.0.2 --port 5000 --payload 1200
```

### On the Host PC

Run `relay.py` from `tools/camera/` using `uv`:

```sh
$ cd tools/camera
$ uv run relay.py --port 5000 --ws-port 8000
```

Then open `http://localhost:8000` in a browser to view the live camera stream.

```
usage: relay.py [-h] [--udp-host UDP_HOST] [--udp-port UDP_PORT] [--ws-host WS_HOST] [--ws-port WS_PORT]

RVComp camera relay

options:
  -h, --help            show this help message and exit
  --udp-host UDP_HOST   UDP bind host
  --udp-port UDP_PORT   UDP bind port
  --ws-host WS_HOST     HTTP/WS bind host
  --ws-port WS_PORT     HTTP/WS bind port
```

## System Configuration

### External Pins

The OV7670 is connected to the PMOD JA and JB headers on the Nexys 4 DDR board.

| Signal            | Direction | Description |
|:------------------|:----------|:------------|
| `xclk`            | Output    | Camera input clock (25 MHz) |
| `pclk`            | Input     | Pixel clock |
| `camera_h_ref`    | Input     | Horizontal sync |
| `camera_v_sync`   | Input     | Vertical sync |
| `din[7:0]`        | Input     | 8-bit pixel data |
| `sioc`            | Output    | I2C clock (SCCB) |
| `siod`            | Inout     | I2C data (SCCB) |

### Camera Driver

An FPGA block captures frames from the OV7670 via I2C (SCCB). Pixel data is converted to 8-bit grayscale and stored in two frame buffers in BRAM (ping-pong). 8-bit grayscale was chosen because fitting two full-resolution color frame buffers in BRAM would exceed the available capacity.

A Linux misc driver (`rvcomp-camera`) exposes the device as `/dev/rvcomp_cam0`. The driver accesses the camera hardware via MMIO polling (no IRQ). It supports `read`, `poll`, and `ioctl` (`RVCOMP_CAM_IOC_G_INFO`, `RVCOMP_CAM_IOC_G_META`).

#### MMIO Map

| Region         | Start         | End           | Description |
|:---------------|:-------------:|:-------------:|:------------|
| CSR            | `0xB000_0000` | `0xB000_0FFF` | Control and status registers |
| Frame aperture | `0xB001_0000` | `0xB002_FFFF` | Ping-pong frame buffer window |

#### CSR Map

All CSRs are 32-bit wide.

| Offset | Name               | Access | Description |
|:------:|:-------------------|:------:|:------------|
| 0x00   | `CAM_REG_ID`       | R      | Device ID |
| 0x04   | `CAM_REG_CTRL`     | R/W    | Control (bit 0: capture enable) |
| 0x08   | `CAM_REG_STATUS`   | R      | Status |
| 0x0C   | `CAM_REG_WIDTH`    | R      | Image width in pixels |
| 0x10   | `CAM_REG_HEIGHT`   | R      | Image height in pixels |
| 0x14   | `CAM_REG_STRIDE`   | R      | Row stride in bytes |
| 0x18   | `CAM_REG_FRAME_BYTES` | R   | Total frame size in bytes |
| 0x1C   | `CAM_REG_SEQ`      | R      | Frame sequence counter |
| 0x20   | `CAM_REG_READY_BANK` | R    | Bank holding the latest complete frame |
| 0x24   | `CAM_REG_READ_BANK`  | R/W  | Bank selected for readout |
| 0x28   | `CAM_REG_DROP_COUNT` | R    | Number of dropped frames |
| 0x2C   | `CAM_REG_GAIN`     | R/W    | Gain control |

### Transmission Program (`cam_tx`)

`cam_tx` is a userspace program that reads frames from `/dev/rvcomp_cam0` and transmits them to the host as UDP datagrams. Each frame is split into chunks with a custom header (`RVCP` magic, sequence number, width, height, chunk index/count) to allow reassembly on the host.

### Client Program (`relay.py`)

`relay.py` runs on the host and acts as a relay between `cam_tx` and the browser. It listens for UDP datagrams from `cam_tx`, reassembles the frame chunks, and broadcasts each completed frame to all connected WebSocket clients. The browser connects to the WebSocket endpoint (`/ws`) and renders each frame on an HTML5 Canvas element.

## Going Further

The current implementation uses CPU-driven (PIO) reads from the BRAM frame buffer and UDP transmission, which limits the achievable frame rate.

Since this runs on an FPGA, the hardware is fully reconfigurable. For example:

- **DMA**: offload frame readout from the CPU entirely
- **FPGA-side Ethernet framing**: generate UDP/IP headers in hardware and push frames to the MAC without CPU involvement
- **Pipeline**: overlap capture and transmission in the FPGA fabric

Changes that would require a full chip respin on an ASIC can be explored here simply by modifying the RTL — feel free to experiment.

## Project Information
This project started June, 2024.
**Project Name**: RVComp\
**Version**: 1.1.0\
**Last Updated**: 2026/03/27

## Contributors
Contributors to this project are as follows:\
[shmrnrk](https://github.com/shmknrk) \
[yuyu5510](https://github.com/yuyu5510) \
[Kise K.](https://github.com/kisek)

We would like to appreciate the contributions from [shmknrk](https://github.com/shmknrk) for his significant contributions to this repository.

## Change History

- **2025-10-31**: v1.0.0 - Initial release
- **2026-03-28**: v1.1.0 - Added Ethernet MAC Controller (RMII/MII), microSD root filesystem support, and various usability improvements. 
