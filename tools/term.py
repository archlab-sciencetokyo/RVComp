#!/usr/bin/python3

# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025 Archlab, Science Tokyo

import serial
import threading
import sys
import time
import argparse
from collections import deque
import platform
import os
import subprocess
from typing import Optional, Any
from tqdm import tqdm
from readkeys import getch, getkey
from readchar import key as keys
from typing import Callable

# Platform-specific imports for terminal mode management only
if platform.system() == 'Windows':
    import ctypes
    from ctypes import wintypes
    import msvcrt
    ENABLE_PROCESSED_INPUT = 0x0001
    ENABLE_LINE_INPUT = 0x0002
    ENABLE_ECHO_INPUT = 0x0004
else:
    import termios
    import tty

load_file = 0 # Flag
lock = threading.Lock() # Lock for load_file access

def flush_input_buffer_windows() -> None:
    """
    Flush the Windows console input buffer to clear any pending keystrokes.
    This is necessary to prevent stray characters from previous sessions
    from being sent to the serial port.
    """
    if platform.system() == 'Windows':
        # Clear all pending characters from the input buffer
        while msvcrt.kbhit():
            msvcrt.getch()

        # Also flush using readkeys if available to clear its internal buffer
        try:
            # Read and discard any buffered input from readkeys
            while True:
                data = getch(NONBLOCK=True, encoding=None)
                if not data:
                    break
        except:
            pass

def set_windows_console_mode() -> Optional[int]:
    """
    Disable Windows console input processing to allow Ctrl+C to be read as a character.

    Returns:
        The original console mode, or None if setting failed.
    """
    if platform.system() != 'Windows':
        return None

    try:
        # Get stdin handle
        kernel32 = ctypes.windll.kernel32
        stdin_handle = kernel32.GetStdHandle(-10)  # STD_INPUT_HANDLE

        # Get current mode
        old_mode = wintypes.DWORD()
        kernel32.GetConsoleMode(stdin_handle, ctypes.byref(old_mode))

        # Disable processed input, line input, and echo
        new_mode = old_mode.value & ~(ENABLE_PROCESSED_INPUT | ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT)
        kernel32.SetConsoleMode(stdin_handle, new_mode)

        return old_mode.value
    except Exception as e:
        print(f"Warning: Could not set Windows console mode: {e}")
        return None

def restore_windows_console_mode(old_mode: Optional[int]) -> None:
    """
    Restore Windows console mode to its original state.

    Args:
        old_mode: The original console mode to restore.
    """
    if platform.system() != 'Windows' or old_mode is None:
        return

    try:
        kernel32 = ctypes.windll.kernel32
        stdin_handle = kernel32.GetStdHandle(-10)  # STD_INPUT_HANDLE
        kernel32.SetConsoleMode(stdin_handle, old_mode)
    except Exception as e:
        print(f"Warning: Could not restore Windows console mode: {e}")

def cleanup(port: Optional[serial.Serial], old_settings: Optional[Any]) -> None:
    """"
    Restore terminal settings and close the serial port.

    Args:
        port: The serial port object to close.
        old_settings: The terminal settings to restore (Unix/Linux only, or Windows console mode).
    """
    if port and port.is_open:
        time.sleep(0.1)
        port.reset_input_buffer()
        port.reset_output_buffer()
        port.close()
        print("\r\nSerial port closed.", end='\r\n')

    # Flush Windows input buffer after port is closed
    flush_input_buffer_windows()

    if old_settings:
        if platform.system() == 'Windows':
            restore_windows_console_mode(old_settings)
        else:
            fd = sys.stdin.fileno()
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
    if old_settings:
        print("Terminal settings restored.", end='\r\n')

def serial_write(port: serial.Serial, load_event: bool = False,
                 filepath: Optional[str] = None, baudrate: int = 115200) -> None:
    """
    Read from stdin and write to the serial port (unified cross-platform version using readkeys).

    Args:
        port: The serial port object to write data to.
        load_event: Is Linux boot mode enabled?
        filepath: Optional path to file to send when load is detected.
        baudrate: Baud rate for calculating chunk size.
    """
    que = deque(maxlen=3)
    byte_buffer = bytearray()

    def write_check_and_send(nonblock: bool = False) -> bool:
        nonlocal byte_buffer
        try:
            # Read raw bytes first
            if platform.system() == 'Windows':
                raw_data = getch(NONBLOCK=nonblock, encoding=None)
            else:
                raw_data = getch(NONBLOCK=nonblock, encoding=None, raw=False)
            if not raw_data:
                return False

            # If we get a string (should not happen with encoding=None, but just in case)
            if isinstance(raw_data, str):
                data = raw_data
            else:
                byte_buffer.extend(raw_data)

                # Try to decode as UTF-8
                try:
                    data = byte_buffer.decode('utf-8')
                    byte_buffer.clear()  # Success, clear buffer
                except UnicodeDecodeError:
                    # Incomplete sequence, wait for more bytes
                    if len(byte_buffer) > 4:
                        byte_buffer.clear()  # Clear invalid data
                    return False

            # Check for exit command
            que.append(data)
            if ''.join(que) == '\x03:q':
                return True

            # Send to serial port
            port.write(data.encode('utf-8'))
        except Exception as e:
            print(f"\r\nError in serial_write: {type(e).__name__}: {e}", end='', flush=True)
            byte_buffer.clear()
            return False
        return False

    if load_event:
        global load_file, lock

        # Load event mode: check for load signal while handling input
        while True:
            with lock:
                if load_file:
                    time.sleep(0.1)
                    success = send_file(port, filepath, baudrate)
                    if not success:
                        return
                    break

            # Use nonblock mode but with longer sleep for stability
            if write_check_and_send(nonblock=True):
                return
            time.sleep(0.01) 

    # Normal mode: use blocking for best input handling
    while True:
        if write_check_and_send(nonblock=False):
            return

def serial_read(port: serial.Serial, load_event: bool = False) -> None:
    """
    Read from the serial port and print to stdout.
    
    Args:
        port: The serial port object to read data from.
        load_event: Is Linux boot mode enabled?
    """
    # Load detection phase
    if load_event:
        global load_file
        global lock
        while port and port.is_open:
            try:
                # Blocking read: waits up to port.timeout (0.1s), zero CPU when idle
                data_bytes = port.read(1)
                if not data_bytes:
                    continue  # timeout, no data
                # Read any remaining buffered data
                remaining = port.in_waiting
                if remaining > 0:
                    data_bytes += port.read(remaining)
                received_data = data_bytes.decode('utf-8', errors='ignore')
                print(received_data, end="", flush=True)
                if '!\x0a' in received_data: 
                    time.sleep(0.1)
                    print("\r\nDetected load signal. Preparing to send file...")
                    with lock:
                        load_file = 1
                    break
            except (serial.SerialException, OSError):
                break
            except Exception as e:
                print(f"\r\nError in serial_read: {e}")
                break
    # Interactive read loop
    while port and port.is_open:
        try:
            # Blocking read: waits up to port.timeout (0.1s), zero CPU when idle
            data_bytes = port.read(1)
            if not data_bytes:
                continue  # timeout, no data
            # Read any remaining buffered data
            remaining = port.in_waiting
            if remaining > 0:
                data_bytes += port.read(remaining)
            received_data = data_bytes.decode('utf-8', errors='ignore')
            print(received_data, end="", flush=True)
        except (serial.SerialException, OSError):
            break
        except Exception as e:
            print(f"\r\nError in serial_read: {e}")
            break

def send_file(port: serial.Serial, filepath: str, baudrate: int = 115200) -> bool:
    """
    Send a binary file through the serial port with progress bar.

    Args:
        port: The serial port object to write data to.
        filepath: Path to the binary file to send.
        baudrate: Baud rate to calculate optimal chunk size (default: 115200).

    Returns:
        True if file was sent successfully, False if aborted or error occurred.
    """
    try:
        chunk_size = max(1024, baudrate // 20)  # Minimum 1024 bytes
        file_size = os.path.getsize(filepath)
        print(f"\r\nSending file: {filepath}\r\n", end='', flush=True)
        print(f"File size: {file_size} bytes\r\n", end='', flush=True)
        print(f"Chunk size: {chunk_size} bytes (based on {baudrate} baud)\r\n", end='', flush=True)
        que = deque(maxlen=3)
        byte_buffer = bytearray()

        with open(filepath, 'rb') as f:
            with tqdm(total=file_size, unit='B', unit_scale=True, unit_divisor=1024, desc="Sending") as pbar:
                while True:
                    chunk = f.read(chunk_size)
                    if not chunk:
                        break
                    port.write(chunk)
                    pbar.update(len(chunk))
                    # User abort check (Ctrl+C:q) sampling 5 times per chunk
                    for _ in range(5):
                        try:
                            # Windows doesn't support 'raw' parameter, use platform-specific call
                            if platform.system() == 'Windows':
                                raw_data = getch(NONBLOCK=True, encoding=None)
                            else:
                                raw_data = getch(NONBLOCK=True, encoding=None, raw=False)
                            if not raw_data:
                                break

                            if isinstance(raw_data, str):
                                data = raw_data
                            else:
                                byte_buffer.extend(raw_data)
                                try:
                                    data = byte_buffer.decode('utf-8')
                                    byte_buffer.clear()
                                except UnicodeDecodeError:
                                    if len(byte_buffer) > 4:
                                        byte_buffer.clear()
                                    continue

                            que.append(data)
                            if ''.join(que) == '\x03:q':
                                print("\r\nFile transfer aborted by user.")
                                port.flush()
                                return False
                        except Exception as e:
                            print(f"Error checking for abort: {e}")
                            byte_buffer.clear()
                            continue

                port.flush()

        print("\r\nFile sent successfully.")
        return True
    except Exception as e:
        print(f"\r\nError sending file: {e}")
        return False

def port_open(portname: str, baudrate: int, bytesize: int, parity: str, 
              stopbits: float, rtscts: bool, xonxoff: bool, dsrdtr: bool, 
              write_timeout: Optional[float], inter_byte_timeout: Optional[float]) -> Optional[serial.Serial]:
    """
    Open the serial port with the specified settings.

    Args:
        portname: The serial port device name (e.g., '/dev/ttyUSB0', 'COM1').
        baudrate: The baud rate for the serial communication (e.g., 9600, 115200).
        bytesize: Number of data bits (5, 6, 7, or 8).
        parity: Parity checking ('N'=None, 'E'=Even, 'O'=Odd, 'M'=Mark, 'S'=Space).
        stopbits: Number of stop bits (1, 1.5, or 2).
        rtscts: Enable RTS/CTS hardware flow control.
        xonxoff: Enable XON/XOFF software flow control.
        dsrdtr: Enable DSR/DTR hardware flow control.
        write_timeout: Write timeout in seconds (None for no timeout).
        inter_byte_timeout: Inter-byte timeout in seconds (None for no timeout).
    
    Returns:
        The opened serial port object, or None if opening failed.
    """
    # Parity mapping for display
    parity_names = {
        'N': 'NONE',
        'E': 'EVEN',
        'O': 'ODD',
        'M': 'MARK',
        'S': 'SPACE'
    }
    
    try:
        port = serial.Serial(
            port=portname,
            baudrate=baudrate,
            bytesize=bytesize,
            parity=parity,
            stopbits=stopbits,
            rtscts=rtscts,
            xonxoff=xonxoff,
            dsrdtr=dsrdtr,
            timeout=0.1,
            write_timeout=write_timeout,
            inter_byte_timeout=inter_byte_timeout
        )
        print(f"Port {port.name} opened successfully.")
        parity_display = parity_names.get(parity, parity)
        print(f"Settings: {baudrate} baud, {bytesize} data bits, parity={parity_display}, stopbits={stopbits}")
        if rtscts:
            print("  RTS/CTS flow control: enabled")
        if xonxoff:
            print("  XON/XOFF flow control: enabled")
        if dsrdtr:
            print("  DSR/DTR flow control: enabled")
        time.sleep(0.2)

        if platform.system() == 'Windows':
            port.reset_input_buffer()
            port.reset_output_buffer()

        return port
    except serial.SerialException as e:
        print(f"Error: Could not open port {portname}. {e}")
        return None
    
def bit_load(method: str) -> None:
    """
    Load FPGA bitstream using the specified method.

    Args:
        method: The bitstream load method ('local' or 'remote').
    """
    try:
        file_dir = os.path.dirname(os.path.abspath(__file__))
        rvcomp_dir = os.path.abspath(os.path.join(file_dir, '..'))
        if method == 'local':
            print("Starting local bitstream load...", end='\r\n')
            result = subprocess.run(['make load'], cwd=rvcomp_dir, shell=True, capture_output=True, text=True)
        elif method == 'remote':
            print("Starting remote bitstream load...", end='\r\n')
            result = subprocess.run(['make remoteload'], cwd=rvcomp_dir, shell=True, capture_output=True, text=True)
        if result.returncode == 0:
            print("Bitstream loaded successfully.", end='\r\n')
        else:
            print(f"Bitstream load failed. Error: {result.stderr}", end='\r\n')
    except Exception as e:
        print(f"Error during bitstream load: {e}", end='\r\n')

def main() -> None:
    """
    Main function to parse arguments and start serial communication.
    
    Parses command-line arguments for serial port configuration,
    opens the port, and starts read/write threads for bidirectional communication.
    """

    parser = argparse.ArgumentParser(
        description='Serial port terminal communication tool',
        formatter_class=argparse.RawTextHelpFormatter,
        epilog='commands:\n   Ctrl+C -> :q\t\tExit the program'
    )

    def make_checker(parameter: str, greater_than: int, cast: Callable[[str], int]) -> Callable[[Optional[str]], int]:
        def checker(value: Optional[str]) -> None:
            if value is not None:
                try:
                    value = cast(value)
                    if value <= greater_than:
                        raise argparse.ArgumentTypeError(f"{parameter} must be greater than {greater_than}")
                    return value
                except ValueError:
                    raise argparse.ArgumentTypeError(f"{parameter} must be an integer")
        return checker
    # Required arguments
    parser.add_argument('port', type=str, help='Serial port device (e.g., /dev/ttyUSB0, COM1)')
    parser.add_argument('baudrate', type=make_checker("Baudrate", 0, int),help='Baud rate (e.g., 9600, 115200)')
    
    # Optional arguments
    parser.add_argument('-b', '--bytesize', type=int, default=8, choices=[5, 6, 7, 8],
                        help='Number of data bits')
    parser.add_argument('-p', '--parity', type=str, default='N', choices=['N', 'E', 'O', 'M', 'S'],
                        help='Parity check: N=NONE, E=EVEN, O=ODD, M=MARK, S=SPACE')
    parser.add_argument('-s', '--stopbits', type=float, default=1, choices=[1, 1.5, 2],
                        help='Number of stop bits')
    parser.add_argument('-r', '--rtscts', action='store_true',
                        help='Enable RTS/CTS hardware flow control')
    parser.add_argument('-x', '--xonxoff', action='store_true',
                        help='Enable XON/XOFF software flow control')
    parser.add_argument('-d', '--dsrdtr', action='store_true',
                        help='Enable DSR/DTR hardware flow control')
    parser.add_argument('-w', '--write-timeout', type=make_checker("Write Timeout", 0, float), default=None,
                        help='Write timeout in seconds')
    parser.add_argument('-i', '--inter-byte-timeout', type=make_checker("Inter-Byte Timeout", 0, float), default=None,
                        help='Inter-byte timeout in seconds')
    parser.add_argument('-f', '--linux-file-path', type=str, default='../image/fw_payload.bin',
                        help='Relative path of linux file to send')
    parser.add_argument('-l', '--linux-boot', action='store_true',
                        help='Linux boot mode: send linux file after detecting load')
    parser.add_argument('--bitstream-load', type=str, default=None, choices=[None, 'local', 'remote'],
                        help='Bitstream load method: local or remote')
    args = parser.parse_args()

    # Get the full path to fw_payload.bin
    script_dir = os.path.dirname(os.path.abspath(__file__))
    fw_payload_path = os.path.join(script_dir, args.linux_file_path)
    fw_payload_path = os.path.abspath(fw_payload_path)
    if args.linux_boot and not os.path.exists(fw_payload_path):
        print(f"Error: File not found at {fw_payload_path}.", file=sys.stderr)
        exit(1)
    if args.linux_boot:
        print("Linux boot mode: waiting for load to send fw_payload.bin...")
        print(f"File to send: {fw_payload_path}")
    port = port_open(args.port, args.baudrate, args.bytesize, args.parity, 
                     args.stopbits, args.rtscts, args.xonxoff, args.dsrdtr,
                     args.write_timeout, args.inter_byte_timeout)

    if args.linux_boot and not os.path.exists(fw_payload_path):
        print(f"Warning: fw_payload.bin not found at {fw_payload_path}. Linux boot mode will fail if used.")
        exit(1)

    if port:
        old_settings = None
        if platform.system() == 'Windows':
            old_settings = set_windows_console_mode()
        else:
            fd = sys.stdin.fileno()
            old_settings = termios.tcgetattr(fd)
            tty.setraw(fd)

        try:
            thread_read = None
            thread_write = None
            thread_load = None

            if args.linux_boot:
                thread_read = threading.Thread(target=serial_read, args=(port, True), daemon=True)
                thread_write = threading.Thread(target=serial_write, args=(port, True, fw_payload_path, args.baudrate), daemon=True)
            else:
                # Normal mode: bidirectional communication
                thread_read = threading.Thread(target=serial_read, args=(port, False), daemon=True)
                thread_write = threading.Thread(target=serial_write, args=(port, False, None, args.baudrate), daemon=True)

            if args.bitstream_load is not None:
                thread_load = threading.Thread(target=bit_load, args=(args.bitstream_load,), daemon=True)

            thread_read.start()
            thread_write.start()
            if thread_load:
                thread_load.start()

            while thread_read.is_alive() and thread_write.is_alive():
                time.sleep(0.1)

        except KeyboardInterrupt:
            pass
        finally:
            cleanup(port, old_settings)
    else:
        print("Exiting due to port open failure.")

if __name__ == '__main__':
    main()