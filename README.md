# RVComp

## Document
If you want to read the document, please visit the [RVComp Documentation Pages](https://archlab-sciencetokyo.github.io/RVComp-doc/).

## Overview
RVComp is a RISC-V SoC (System on Chip) with a five-stage pipeline. It supports the RV32IMASU_Zicntr_Zicsr_Zifencei instruction set, including privileged modes and the Sv32 virtual memory system, so it can run Linux. The RVComp project began in June 2024 and offers the following characteristics:

- **High operating frequency**: Achieves a maximum clock frequency of **170 MHz** on a Nexys A7-100T (XC7A100T-1CSG324C)
- **HDL implementation**: About 7,757 lines of Verilog HDL (as of October 2025), with a from-scratch design except for the DRAM controller and clock generation
- **Permissive licensing**: All HDL components except IP are provided under the MIT license

## LICENSE

RVComp files we developed from scratch are distributed under the [MIT license](https://opensource.org/licenses/MIT), so the project source code can be freely used, modified, and redistributed. 

However, please note that the RVComp project uses multiple open-source components.
The following components follow their respective licenses; see the LICENSE file for full details.

- **DRAM controller**: [Xilinx MIG](https://www.amd.com/en/products/adaptive-socs-and-fpgas/intellectual-property/mig.html#documentation) ([Xilinx End User License Agreement](https://account.amd.com/content/dam/account/en/licenses/download/end-user-license-agreement.pdf))
- **Clock generation**: Xilinx Clocking Wizard ([Xilinx End User License Agreement](https://account.amd.com/content/dam/account/en/licenses/download/end-user-license-agreement.pdf))
- **prog/coremark**: [CoreMark-PRO](https://www.eembc.org/coremark-pro/) ([EEMBC License + Apache License 2.0](https://github.com/eembc/coremark-pro?tab=License-1-ov-file))
- **prog/embench**: [Embench-IoT](https://github.com/embench/embench-iot) ([GPL-3.0 License](https://github.com/embench/embench-iot?tab=GPL-3.0-1-ov-file))
- **prog/riscv-tests**: [riscv-tests](https://github.com/riscv/riscv-tests) ([The Regents of the University of California (Regents)](https://github.com/riscv-software-src/riscv-tests?tab=License-1-ov-file))

- **OpenSBI**: [OpenSBI for customized for RVComp](https://github.com/archlab-sciencetokyo/opensbi.git) ([BSD-2-Clause License](https://github.com/archlab-sciencetokyo/opensbi?tab=License-1-ov-file))


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


## Quick Start
This section is the same of [quick start of Document](https://archlab-sciencetokyo.github.io/RVComp-doc/intro/quickstart.html).

This section explains how to run RVComp on an FPGA board using a prebuilt bitstream and Linux image. 
Please Download the following files from [the release page](https://github.com/archlab-sciencetokyo/RVComp/releases).
- `fw_payload.bin`: Linux image file
- `arty_a7.bit`: Bitstream for Arty A7 35T FPGA board
- `nexys4ddr.bit`: Bitstream for Nexys 4 DDR FPGA
- `tools.zip` : Programs to communicate with the FPGA board via UART.
Please unzip `tools.zip`.


Please make sure the necessary tools and the FPGA board are ready:
- {ref}`Vivado (2024.1 recommended) <vivado>`
- {ref}`uv <uv>`
- FPGA board (Nexys 4 DDR or Arty A7 35T)

Guidance for WSL2 usage will be added to this section later.

1. Please connect the FPGA board to your PC.
2. Please download and extract `fw_payload.bin`, `arty_a7.bit` (for Arty A7 35T), `nexys4ddr.bit` (for Nexys 4 DDR), and the `tools` directory from the archive mentioned above, and place them in the same directory.
3. Please determine which serial port the USB connection is using. See [Checking the Serial Port](#checking-the-serial-port) below.
4. Please open PowerShell (Windows) or a terminal (Linux) and change to the directory from step 2.
5. Please run the following command, replacing `<port>` with the value from step 3. On success you should see `Port <port> opened successfully.`.
   - Nexys 4 DDR: `cd tools && uv run term <port> 3200000 --linux-boot --linux-file-path ../image/fw_payload.bin`
   - Arty A7 35T: `cd tools && uv run term <port> 3300000 --linux-boot --linux-file-path ../image/fw_payload.bin`
6. Please launch Vivado and select **Open Hardware Manager → Open Target → Auto Connect → Program Device**.
7. When prompted for the bitstream, please choose `arty_a7.bit` if you use Arty A7, or `nexys4ddr.bit` if you use Nexys 4 DDR, then click **Program**.
8. The Linux image is transferred to the FPGA and boot begins. Once the login prompt appears, please log in as `root` (no password).
9. Please press `Ctrl+C`, then type `:q` to exit the serial console.

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

