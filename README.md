# RVComp

## Document
If you want to read the document, please visit the [RVComp Documentation Pages](https://archlab-sciencetokyo.github.io/RVComp-doc/).

[Demo](https://archlab-sciencetokyo.github.io/RVComp-doc/intro/demo.html) is here.

## Overview
RVComp is a RISC-V SoC (System on Chip) with a five-stage pipeline. It supports the RV32IMASU_Zicntr_Zicsr_Zifencei instruction set, including privileged modes and the Sv32 virtual memory system, so it can run Linux. The RVComp project began in June 2024 and offers the following characteristics:

- **High operating frequency**: Achieves a maximum clock frequency of **170 MHz** (Version 1.0.0.0) on a Nexys A7-100T (XC7A100T-1CSG324C)
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


# Quick Start

This section explains how to run RVComp on an FPGA board using a prebuilt bitstream and Linux image.


Please download the following files from [the release page](https://github.com/archlab-sciencetokyo/RVComp/releases).

**UART boot (Arty A7 35T or Nexys 4 DDR):**
- `uart_fw_payload.bin`: Linux image file for UART boot
- `uart_arty_a7.bit`: Bitstream for Arty A7 35T (UART boot)
- `uart_nexys4ddr.bit`: Bitstream for Nexys 4 DDR (UART boot)

**MMC boot (Nexys 4 DDR only):**
- `mmc_fw_payload.bin`: Linux image for MMC boot
- `mmc_nexys4ddr.bit`: Bitstream for Nexys 4 DDR (MMC boot)

```{note}
MMC boot requires a microSD card inserted into the Nexys 4 DDR board's microSD slot.
If an Ethernet cable is connected to the board, the network interface is available after boot.
```

**Common:**
- `tools.zip`: Programs to communicate with the FPGA board via UART

Please unzip `tools.zip`.

Please make sure the necessary tools and the FPGA board are ready:
- {ref}`Vivado (2024.1 recommended) <vivado>`
- {ref}`uv <uv>`
- FPGA board (Nexys 4 DDR or Arty A7 35T)





## UART Boot (Arty A7 35T or Nexys 4 DDR)

1. Please connect the FPGA board to your PC.
2. Please download and extract `uart_fw_payload.bin`, `uart_arty_a7.bit` (for Arty A7 35T) or `uart_nexys4ddr.bit` (for Nexys 4 DDR), and the `tools` directory from the archive mentioned above, and place them in the same directory.
3. Please determine which serial port the USB connection is using. See [Checking the Serial Port](#checking-the-serial-port) below.
4. Please open PowerShell (Windows) or a terminal (Linux) and change to the directory from step 2.
5. Please run the following command, replacing `<port>` with the value from step 3. On success you should see `Port <port> opened successfully.`.
   - Nexys 4 DDR: `cd tools && uv run term <port> 3000000 --linux-boot --linux-file-path ../uart_fw_payload.bin`
   - Arty A7 35T: `cd tools && uv run term <port> 3000000 --linux-boot --linux-file-path ../uart_fw_payload.bin`
6. Please launch Vivado and select **Open Hardware Manager → Open Target → Auto Connect → Program Device**.
7. When prompted for the bitstream, please choose `uart_arty_a7.bit` if you use Arty A7, or `uart_nexys4ddr.bit` if you use Nexys 4 DDR, then click **Program**.
8. The Linux image is transferred to the FPGA and boot begins. Once the login prompt appears, please log in as `root` (no password).
9. To use Ethernet, configure the network interface:
   ```sh
   $ ip addr add <IP_ADDRESS>/<PREFIX_LEN> dev eth0
   $ ip link set eth0 up
   ```
10. Please press `Ctrl+C`, then type `:q` to exit the serial console.





## MMC Boot (Nexys 4 DDR only)

MMC boot on Nexys 4 DDR requires a microSD card. The `mmc_fw_payload.bin` file is a combined binary containing the Linux image and root filesystem; it is written to the beginning of the microSD card. The serial terminal is still used as a console, but it does not send the Linux image in this mode.

### Writing the microSD card

Insert a microSD card into your host machine.

**Linux:**

Identify the block device node with `lsblk` or `dmesg`. **Verify the device node carefully before proceeding; writing to the wrong device will permanently destroy data on that device.**

```bash
$ sudo dd if=mmc_fw_payload.bin of=/dev/sdX bs=1M conv=fsync,notrunc status=progress
```

Replace `/dev/sdX` with the actual device node of your microSD card (for example `/dev/sdb`). After the command completes, safely eject the card.

**Windows (WSL):**

Attach the microSD card to WSL, then use the same `dd` command as Linux above.

- USB microSD card reader: follow [this guide (usbipd)](https://learn.microsoft.com/en-us/windows/wsl/connect-usb) to bind the device to WSL.
- Built-in card reader: follow [this guide (WSL2 disk mounting)](https://learn.microsoft.com/en-us/windows/wsl/wsl2-mount-disk) to mount the disk in WSL.

### Booting from microSD card

1. Insert the written microSD card into the microSD slot on the Nexys 4 DDR board.
2. Connect the board to your PC via USB.
3. Determine the serial port as described in [Checking the Serial Port](#checking-the-serial-port).
4. Open a terminal and run the following command. No `--linux-boot` flag is **needed** because the serial tool is used only as a console in this mode:
   ```bash
   $ cd tools && uv run term <port> 3000000
   ```
5. Launch Vivado and program the board with `mmc_nexys4ddr.bit` using **Open Hardware Manager → Open Target → Auto Connect → Program Device**.
6. The bootrom copies the Linux image from the microSD card into DRAM and boots Linux. The root filesystem on the microSD card is mounted as `/dev/mmcblk0`. Once the login prompt appears, log in as `root` (no password).
7. To use Ethernet, configure the network interface:
   ```sh
   $ ip addr add <IP_ADDRESS>/<PREFIX_LEN> dev eth0
   $ ip link set eth0 up
   ```
8. Press `Ctrl+C`, then type `:q` to exit the serial console.



(checking-the-serial-port)=
## Checking the Serial Port

### Windows

Please run the following command in PowerShell:

```powershell
Get-CimInstance Win32_PnPEntity | Where-Object { $_.Caption -match 'COM' } | Select-Object Caption, DeviceID
```

Please identify the entry whose `DeviceID` contains `FTDI`; this corresponds to the FPGA board. It appears in the form `USB Serial Device (COM*)`. Please note the COM port name.

### WSL

Please follow the instructions in [this article](https://learn.microsoft.com/en-us/windows/wsl/connect-usb) to attach USB devices to WSL. Please run `usbipd list`; the entry with `VID:PID` of `0403:6010` is usually the FPGA board. After attaching it, please follow the Linux instructions below.

### Linux

Please run the following command in a terminal:

```bash
$ ls /dev/ttyUSB*
```

The available USB serial ports are listed. If only one FPGA board is connected as a USB serial device, it is typically `/dev/ttyUSB1`. When multiple USB serial devices are present, please run the command below for each port and look for a device where `ID_VENDOR` is `Digilent`:

```bash
$ udevadm info /dev/ttyUSB1 | grep ID_VENDOR=
```

Please record the `/dev/ttyUSB*` path assigned to the FPGA board.


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
