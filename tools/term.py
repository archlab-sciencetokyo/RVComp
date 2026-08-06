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
from typing import Callable, Optional, Any
from tqdm import tqdm
from readkeys import getch

# Platform-specific imports for terminal mode management only
if platform.system() == 'Windows':
    import ctypes
    from ctypes import wintypes
    import msvcrt
    STD_INPUT_HANDLE = -10
    STD_OUTPUT_HANDLE = -11
    ENABLE_PROCESSED_INPUT = 0x0001
    ENABLE_LINE_INPUT = 0x0002
    ENABLE_ECHO_INPUT = 0x0004
    ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004
else:
    import termios
    import tty

load_file = 0 # Flag
lock = threading.Lock() # Lock for load_file access
store_ack = threading.Semaphore(0)

EXIT_SEQUENCE = '\x03:q'
LOAD_SIGNAL = b'!\n'
LINUX_SD_STORE_CHUNK_SIZE = 4096
LINUX_SD_STORE_SIZE = 167772160
FNV1A32_OFFSET = 0x811C9DC5
FNV1A32_PRIME = 0x01000193
SERIAL_IO_POLL_INTERVAL = 0.01
SERIAL_THREAD_JOIN_TIMEOUT = 1.0

WINDOWS_EXTENDED_KEY_PREFIXES = ('\x00', '\xe0')
WINDOWS_NAV_CODES = {
    'H': '\x1b[A',   # Up
    'P': '\x1b[B',   # Down
    'K': '\x1b[D',   # Left
    'M': '\x1b[C',   # Right
    'G': '\x1b[H',   # Home
    'O': '\x1b[F',   # End
    'R': '\x1b[2~',  # Insert
    'S': '\x1b[3~',  # Delete
    'I': '\x1b[5~',  # Page up
    'Q': '\x1b[6~',  # Page down
}
WINDOWS_FN_CODES = {
    ';': '\x1bOP',
    '<': '\x1bOQ',
    '=': '\x1bOR',
    '>': '\x1bOS',
    '?': '\x1b[15~',
    '@': '\x1b[17~',
    'A': '\x1b[18~',
    'B': '\x1b[19~',
    'C': '\x1b[20~',
    'D': '\x1b[21~',
}

def normalize_windows_key(first: str, read_next: Callable[[], str]) -> Optional[str]:
    """
    Translate Windows console scan-code keys to the VT sequences expected by
    Linux shells and line editors on the serial side.
    """
    if first not in WINDOWS_EXTENDED_KEY_PREFIXES:
        return first

    code = read_next()
    if first == '\x00':
        return WINDOWS_FN_CODES.get(code)
    return WINDOWS_NAV_CODES.get(code)

def read_console_key(nonblock: bool = False) -> Optional[str]:
    """Read one console key, normalized for serial transmission."""
    if platform.system() == 'Windows':
        if nonblock and not msvcrt.kbhit():
            return None
        return normalize_windows_key(msvcrt.getwch(), msvcrt.getwch)

    data = getch(NONBLOCK=nonblock, encoding=None, raw=False)
    return data or None

def encode_serial_key(key: Optional[str]) -> Optional[bytes]:
    """Encode a normalized console key for the serial port."""
    if not key:
        return None
    return key.encode('utf-8')

def update_exit_queue(que: deque[str], key: str) -> bool:
    """Return True once Ctrl+C followed by :q has been typed."""
    for char in key:
        que.append(char)
        if ''.join(que) == EXIT_SEQUENCE:
            return True
    return False

def write_stdout_bytes(data: bytes) -> None:
    """Write serial output bytes without Python text newline translation."""
    if not data:
        return
    try:
        os.write(sys.stdout.fileno(), data)
    except (AttributeError, OSError, ValueError):
        if hasattr(sys.stdout, 'buffer'):
            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()
        else:
            sys.stdout.write(data.decode('utf-8', errors='replace'))
            sys.stdout.flush()

def count_load_signals(pending: bytes, data: bytes) -> tuple[int, bytes]:
    """Count complete bootrom load signals, preserving a split trailing byte."""
    scan = pending + data
    keep = len(LOAD_SIGNAL) - 1
    return scan.count(LOAD_SIGNAL), scan[-keep:] if keep else b''

def split_load_signals(pending: bytes, data: bytes) -> tuple[int, bytes, bytes]:
    """Remove bootrom ACKs from visible output while counting them."""
    scan = pending + data
    visible = bytearray()
    count = 0
    index = 0

    while index < len(scan):
        if scan.startswith(LOAD_SIGNAL, index):
            count += 1
            index += len(LOAD_SIGNAL)
            continue
        if scan[index:index + 1] == LOAD_SIGNAL[:1] and index == len(scan) - 1:
            return count, scan[index:], bytes(visible)
        visible.append(scan[index])
        index += 1

    return count, b'', bytes(visible)

def fnv1a32_update(hash_value: int, data: bytes) -> int:
    """Update a 32-bit FNV-1a checksum."""
    for byte in data:
        hash_value ^= byte
        hash_value = (hash_value * FNV1A32_PRIME) & 0xFFFFFFFF
    return hash_value

def flush_input_buffer_windows() -> None:
    """
    Flush the Windows console input buffer to clear any pending keystrokes.
    This is necessary to prevent stray characters from previous sessions
    from being sent to the serial port.
    """
    if platform.system() == 'Windows':
        # Clear all pending characters from the input buffer
        while msvcrt.kbhit():
            msvcrt.getwch()

def set_windows_console_mode() -> Optional[Any]:
    """
    Disable Windows console input processing to allow Ctrl+C to be read as a character.

    Returns:
        The original console settings, or None if setting failed.
    """
    if platform.system() != 'Windows':
        return None

    try:
        # Get stdin handle
        kernel32 = ctypes.windll.kernel32
        stdin_handle = kernel32.GetStdHandle(STD_INPUT_HANDLE)
        stdout_handle = kernel32.GetStdHandle(STD_OUTPUT_HANDLE)

        # Get current mode
        old_input_mode = wintypes.DWORD()
        old_output_mode = wintypes.DWORD()
        kernel32.GetConsoleMode(stdin_handle, ctypes.byref(old_input_mode))
        have_output_mode = bool(kernel32.GetConsoleMode(stdout_handle, ctypes.byref(old_output_mode)))
        old_input_cp = kernel32.GetConsoleCP()
        old_output_cp = kernel32.GetConsoleOutputCP()

        # Disable processed input, line input, and echo
        new_input_mode = old_input_mode.value & ~(ENABLE_PROCESSED_INPUT | ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT)
        kernel32.SetConsoleMode(stdin_handle, new_input_mode)
        kernel32.SetConsoleCP(65001)
        kernel32.SetConsoleOutputCP(65001)
        if have_output_mode:
            kernel32.SetConsoleMode(stdout_handle, old_output_mode.value | ENABLE_VIRTUAL_TERMINAL_PROCESSING)

        return {
            'input_mode': old_input_mode.value,
            'output_mode': old_output_mode.value if have_output_mode else None,
            'input_cp': old_input_cp,
            'output_cp': old_output_cp,
        }
    except Exception as e:
        print(f"Warning: Could not set Windows console mode: {e}")
        return None

def restore_windows_console_mode(old_mode: Optional[Any]) -> None:
    """
    Restore Windows console mode to its original state.

    Args:
        old_mode: The original console mode to restore.
    """
    if platform.system() != 'Windows' or old_mode is None:
        return

    try:
        kernel32 = ctypes.windll.kernel32
        stdin_handle = kernel32.GetStdHandle(STD_INPUT_HANDLE)
        stdout_handle = kernel32.GetStdHandle(STD_OUTPUT_HANDLE)
        if isinstance(old_mode, dict):
            kernel32.SetConsoleMode(stdin_handle, old_mode['input_mode'])
            if old_mode.get('output_mode') is not None:
                kernel32.SetConsoleMode(stdout_handle, old_mode['output_mode'])
            kernel32.SetConsoleCP(old_mode['input_cp'])
            kernel32.SetConsoleOutputCP(old_mode['output_cp'])
        else:
            kernel32.SetConsoleMode(stdin_handle, old_mode)
    except Exception as e:
        print(f"Warning: Could not restore Windows console mode: {e}")

def signal_serial_error(source: str, error: BaseException,
                        stop_event: Optional[threading.Event],
                        error_event: Optional[threading.Event]) -> None:
    """Stop the current I/O session and mark it for exit status 1."""
    already_reported = error_event is not None and error_event.is_set()
    if not already_reported:
        print(
            f"\r\nError in {source}: "
            f"{type(error).__name__}: {error}",
            end='\r\n',
            flush=True,
        )
    if error_event is not None:
        error_event.set()
    if stop_event is not None:
        stop_event.set()


def close_serial_port(port: Optional[serial.Serial], announce: bool = True) -> bool:
    """Close a serial port without aborting a concurrent write via PurgeComm."""
    if port is None:
        return True
    try:
        was_open = bool(port.is_open)
    except Exception:
        was_open = True
    if not was_open:
        return True

    closed = True
    try:
        port.close()
    except Exception as e:
        closed = False
        # A disconnected Windows device can retain is_open=True while its
        # underlying HANDLE is already invalid. Terminal restoration must
        # still proceed in that case.
        print(f"\r\nWarning: Could not close serial port cleanly: {e}", end='\r\n')
    if announce:
        print("\r\nSerial port closed.", end='\r\n')
    return closed


def stop_serial_threads(port: Optional[serial.Serial], stop_event: threading.Event,
                        threads: list[threading.Thread]) -> bool:
    """Cancel pending serial I/O and return whether both workers stopped."""
    stop_event.set()
    cancel_failed = False
    if port is not None:
        for method_name in ('cancel_read', 'cancel_write'):
            method = getattr(port, method_name, None)
            if method is None:
                continue
            try:
                method()
            except Exception as e:
                cancel_failed = True
                print(f"\r\nWarning: Could not {method_name}: {e}", end='\r\n')

    current_thread = threading.current_thread()
    for thread in threads:
        if thread is not current_thread and thread.is_alive():
            thread.join(timeout=SERIAL_THREAD_JOIN_TIMEOUT)

    remaining = [
        thread for thread in threads
        if thread is not current_thread and thread.is_alive()
    ]
    if remaining:
        # Closing is the last-resort unblock for a driver that ignored the
        # cancel request. The stop event prevents either worker from starting
        # another operation on this handle.
        if not close_serial_port(port, announce=False):
            cancel_failed = True
        for thread in remaining:
            thread.join(timeout=SERIAL_THREAD_JOIN_TIMEOUT)

    stopped = not cancel_failed and all(
        thread is current_thread or not thread.is_alive()
        for thread in threads
    )
    if not stopped:
        print(
            "\r\nWarning: Serial worker did not stop.",
            end='\r\n',
        )
    return stopped


def cleanup(port: Optional[serial.Serial], old_settings: Optional[Any]) -> bool:
    """
    Restore terminal settings and close the serial port.

    Args:
        port: The serial port object to close.
        old_settings: The terminal settings to restore (Unix/Linux only, or Windows console mode).
    """
    success = close_serial_port(port)
    try:
        # Flush pending Windows console input after the serial port closes.
        flush_input_buffer_windows()
    except Exception as e:
        success = False
        print(f"Warning: Could not flush console input: {e}", end='\r\n')
    finally:
        if old_settings:
            if platform.system() == 'Windows':
                restore_windows_console_mode(old_settings)
            else:
                fd = sys.stdin.fileno()
                termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
            print("Terminal settings restored.", end='\r\n')
    return success

def serial_write(port: serial.Serial, load_event: bool = False,
                 filepath: Optional[str] = None, baudrate: int = 115200,
                 linux_sd_store: bool = False,
                 store_size: Optional[int] = None,
                 store_chunk_size: int = LINUX_SD_STORE_CHUNK_SIZE,
                 stop_event: Optional[threading.Event] = None,
                 error_event: Optional[threading.Event] = None) -> None:
    """
    Read from stdin and write to the serial port (unified cross-platform version using readkeys).

    Args:
        port: The serial port object to write data to.
        load_event: Is Linux boot mode enabled?
        filepath: Optional path to file to send when load is detected.
        baudrate: Baud rate for calculating chunk size.
        linux_sd_store: Send one chunk per bootrom store ACK.
        store_size: Expected store image size in bytes.
        store_chunk_size: Bytes sent for each bootrom store ACK.
        stop_event: Stops this I/O session when set.
        error_event: Set when main must exit with status 1.
    """
    que = deque(maxlen=3)

    def write_check_and_send(nonblock: bool = False) -> bool:
        try:
            key = read_console_key(nonblock=nonblock)
        except Exception as e:
            signal_serial_error('serial_write', e, stop_event, error_event)
            return True

        if not key:
            return False

        # Check for exit command
        if update_exit_queue(que, key):
            if stop_event is not None:
                stop_event.set()
            return True

        if stop_event is not None and stop_event.is_set():
            return True

        # Send to serial port. Every exception terminates the process with
        # status 1 after main has stopped both workers and restored the console.
        data = encode_serial_key(key)
        if data:
            try:
                port.write(data)
            except serial.SerialTimeoutException as e:
                signal_serial_error('serial_write', e, stop_event, error_event)
                return True
            except (serial.SerialException, OSError) as e:
                signal_serial_error('serial_write', e, stop_event, error_event)
                return True
            except Exception as e:
                signal_serial_error('serial_write', e, stop_event, error_event)
                return True
        return False

    if load_event:
        global load_file, lock

        if linux_sd_store:
            success = send_file_on_acks(
                port,
                filepath,
                store_size,
                store_chunk_size,
                stop_event,
                error_event,
            )
            if not success:
                if stop_event is not None and not stop_event.is_set():
                    stop_event.set()
                return
            if stop_event is not None:
                stop_event.set()
            return

        # Load event mode: check for load signal while handling input
        while stop_event is None or not stop_event.is_set():
            with lock:
                if load_file:
                    time.sleep(0.1)
                    success = send_file(
                        port,
                        filepath,
                        baudrate,
                        stop_event,
                        error_event,
                    )
                    if not success:
                        if stop_event is not None and not stop_event.is_set():
                            stop_event.set()
                        return
                    break

            # Use nonblock mode but with longer sleep for stability
            if write_check_and_send(nonblock=True):
                return
            if stop_event is not None:
                stop_event.wait(SERIAL_IO_POLL_INTERVAL)
            else:
                time.sleep(SERIAL_IO_POLL_INTERVAL)

    if stop_event is None or platform.system() != 'Windows':
        # Preserve blocking console input for standalone calls and POSIX.
        while stop_event is None or not stop_event.is_set():
            if write_check_and_send(nonblock=False):
                return
    else:
        # Polling lets main stop and join the Windows console thread before it
        # closes the serial HANDLE.
        while not stop_event.is_set():
            if write_check_and_send(nonblock=True):
                return
            stop_event.wait(SERIAL_IO_POLL_INTERVAL)

def serial_read(port: serial.Serial, load_event: bool = False,
                linux_sd_store: bool = False,
                stop_event: Optional[threading.Event] = None,
                error_event: Optional[threading.Event] = None) -> None:
    """
    Read from the serial port and print to stdout.
    
    Args:
        port: The serial port object to read data from.
        load_event: Is Linux boot mode enabled?
        linux_sd_store: Treat every load signal as a chunk ACK.
        stop_event: Stops this I/O session when set.
        error_event: Set when main must exit with status 1.
    """
    # Load detection phase
    if load_event:
        global load_file
        global lock
        pending_signal = b''
        while (port and port.is_open and
               (stop_event is None or not stop_event.is_set())):
            try:
                # Blocking read: waits up to port.timeout (0.1s), zero CPU when idle
                data_bytes = port.read(1)
                if not data_bytes:
                    continue  # timeout, no data
                # Read any remaining buffered data
                remaining = port.in_waiting
                if remaining > 0:
                    data_bytes += port.read(remaining)
                if linux_sd_store:
                    signal_count, pending_signal, visible_data = split_load_signals(pending_signal, data_bytes)
                    write_stdout_bytes(visible_data)
                    for _ in range(signal_count):
                        store_ack.release()
                    continue

                write_stdout_bytes(data_bytes)
                signal_count, pending_signal = count_load_signals(pending_signal, data_bytes)
                if signal_count:
                    time.sleep(0.1)
                    print("\r\nDetected load signal. Preparing to send file...")
                    with lock:
                        load_file = 1
                    break
            except Exception as e:
                signal_serial_error('serial_read', e, stop_event, error_event)
                break
    # Interactive read loop
    while (port and port.is_open and
           (stop_event is None or not stop_event.is_set())):
        try:
            # Blocking read: waits up to port.timeout (0.1s), zero CPU when idle
            data_bytes = port.read(1)
            if not data_bytes:
                continue  # timeout, no data
            # Read any remaining buffered data
            remaining = port.in_waiting
            if remaining > 0:
                data_bytes += port.read(remaining)
            write_stdout_bytes(data_bytes)
        except Exception as e:
            signal_serial_error('serial_read', e, stop_event, error_event)
            break

def send_file(port: serial.Serial, filepath: str, baudrate: int = 115200,
              stop_event: Optional[threading.Event] = None,
              error_event: Optional[threading.Event] = None) -> bool:
    """
    Send a binary file through the serial port with progress bar.

    Args:
        port: The serial port object to write data to.
        filepath: Path to the binary file to send.
        baudrate: Baud rate to calculate optimal chunk size (default: 115200).
        stop_event: Stops the transfer when set.
        error_event: Set when main must exit with status 1.

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

        with open(filepath, 'rb') as f:
            with tqdm(total=file_size, unit='B', unit_scale=True, unit_divisor=1024, desc="Sending") as pbar:
                while True:
                    if stop_event is not None and stop_event.is_set():
                        return False
                    chunk = f.read(chunk_size)
                    if not chunk:
                        break
                    port.write(chunk)
                    pbar.update(len(chunk))
                    # User abort check (Ctrl+C:q) sampling 5 times per chunk
                    for _ in range(5):
                        key = read_console_key(nonblock=True)
                        if not key:
                            break

                        if update_exit_queue(que, key):
                            print("\r\nFile transfer aborted by user.")
                            if stop_event is not None:
                                stop_event.set()
                            port.flush()
                            return False

                port.flush()

        print("\r\nFile sent successfully.")
        return True
    except Exception as e:
        signal_serial_error('send_file', e, stop_event, error_event)
        return False

def wait_for_store_ack(que: deque[str],
                       stop_event: Optional[threading.Event] = None) -> bool:
    """Wait for one bootrom ACK while still allowing Ctrl+C:q abort."""
    while stop_event is None or not stop_event.is_set():
        if store_ack.acquire(timeout=0.05):
            return True
        key = read_console_key(nonblock=True)
        if key and update_exit_queue(que, key):
            print("\r\nFile transfer aborted by user.")
            if stop_event is not None:
                stop_event.set()
            return False
    return False

def send_file_on_acks(port: serial.Serial, filepath: Optional[str],
                      expected_size: Optional[int],
                      chunk_size: int = LINUX_SD_STORE_CHUNK_SIZE,
                      stop_event: Optional[threading.Event] = None,
                      error_event: Optional[threading.Event] = None) -> bool:
    """
    Send a binary file one chunk at a time after bootrom ACKs.

    This keeps the board's UART RX FIFO from filling while bootrom waits for
    SD card reads or dirty-line write-backs.
    """
    if filepath is None:
        print("\r\nError sending file: no filepath specified")
        return False

    try:
        file_size = os.path.getsize(filepath)
        if expected_size is not None and file_size != expected_size:
            print(
                f"\r\nError: file size {file_size} bytes does not match "
                f"expected store size {expected_size} bytes."
            )
            return False

        print(f"\r\nSending file to SD: {filepath}\r\n", end='', flush=True)
        print(f"File size: {file_size} bytes\r\n", end='', flush=True)
        print(f"Chunk size: {chunk_size} bytes per bootrom ACK\r\n", end='', flush=True)
        que = deque(maxlen=3)
        sent = 0
        hash_value = FNV1A32_OFFSET

        with open(filepath, 'rb') as f:
            with tqdm(total=file_size, unit='B', unit_scale=True, unit_divisor=1024, desc="Sending") as pbar:
                while sent < file_size:
                    if not wait_for_store_ack(que, stop_event):
                        port.flush()
                        return False

                    chunk = f.read(min(chunk_size, file_size - sent))
                    if not chunk:
                        break

                    port.write(chunk)
                    port.flush()
                    sent += len(chunk)
                    hash_value = fnv1a32_update(hash_value, chunk)
                    pbar.update(len(chunk))

        print(f"\r\nFile sent successfully. fnv1a32=0x{hash_value:08X}")
        return sent == file_size
    except Exception as e:
        signal_serial_error('send_file_on_acks', e, stop_event, error_event)
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
    parser.add_argument('-f', '--file-path',
                        dest='linux_file_path', type=str, default='../image/fw_payload.bin',
                        help='Relative path of linux file to send')
    parser.add_argument('-l', '--linux-boot', action='store_true',
                        help='Linux boot mode: send linux file after detecting load')
    parser.add_argument('--linux-sd-store', action='store_true',
                        help='Send linux file to bootrom SD store mode, one 4 KiB chunk per ACK')
    parser.add_argument('--linux-store-size', type=make_checker("Linux Store Size", 0, int),
                        default=LINUX_SD_STORE_SIZE, metavar="bytes",
                        help='Expected linux file size for SD store mode')
    parser.add_argument('--linux-store-chunk-size', type=make_checker("Linux Store Chunk Size", 0, int),
                        default=LINUX_SD_STORE_CHUNK_SIZE, metavar="bytes",
                        help='Bytes to send for each SD store ACK')
    parser.add_argument('--bitstream-load', type=str, default=None, choices=[None, 'local', 'remote'],
                        help='Bitstream load method: local or remote')
    args = parser.parse_args()
    load_mode = args.linux_boot or args.linux_sd_store

    # Get the full path to fw_payload.bin
    script_dir = os.path.dirname(os.path.abspath(__file__))
    fw_payload_path = os.path.join(script_dir, args.linux_file_path)
    fw_payload_path = os.path.abspath(fw_payload_path)
    if load_mode and not os.path.exists(fw_payload_path):
        print(f"Error: File not found at {fw_payload_path}.", file=sys.stderr)
        sys.exit(1)
    if load_mode:
        if args.linux_sd_store:
            print("Linux SD store mode: waiting for bootrom ACKs to send fw_payload.bin...")
        else:
            print("Linux boot mode: waiting for load to send fw_payload.bin...")
        print(f"File to send: {fw_payload_path}")
    port = port_open(args.port, args.baudrate, args.bytesize, args.parity, 
                     args.stopbits, args.rtscts, args.xonxoff, args.dsrdtr,
                     args.write_timeout, args.inter_byte_timeout)

    if not port:
        print("Exiting due to port open failure.")
        sys.exit(1)

    old_settings = None
    if platform.system() == 'Windows':
        old_settings = set_windows_console_mode()
    else:
        fd = sys.stdin.fileno()
        old_settings = termios.tcgetattr(fd)
        tty.setraw(fd)

    stop_event = threading.Event()
    error_event = threading.Event()
    thread_read = threading.Thread(
        target=serial_read,
        args=(port,),
        kwargs={
            'load_event': load_mode,
            'linux_sd_store': args.linux_sd_store,
            'stop_event': stop_event,
            'error_event': error_event,
        },
        daemon=True,
    )
    thread_write = threading.Thread(
        target=serial_write,
        args=(port,),
        kwargs={
            'load_event': load_mode,
            'filepath': fw_payload_path if load_mode else None,
            'baudrate': args.baudrate,
            'linux_sd_store': args.linux_sd_store,
            'store_size': args.linux_store_size,
            'store_chunk_size': args.linux_store_chunk_size,
            'stop_event': stop_event,
            'error_event': error_event,
        },
        daemon=True,
    )

    try:
        if args.bitstream_load is not None:
            threading.Thread(
                target=bit_load,
                args=(args.bitstream_load,),
                daemon=True,
            ).start()

        thread_read.start()
        thread_write.start()
        while thread_read.is_alive() and thread_write.is_alive():
            if stop_event.wait(0.1):
                break
        if not stop_event.is_set():
            stop_event.set()
    except KeyboardInterrupt:
        stop_event.set()
    except Exception as e:
        signal_serial_error('main', e, stop_event, error_event)
    finally:
        if not stop_serial_threads(port, stop_event, [thread_read, thread_write]):
            error_event.set()
        if not cleanup(port, old_settings):
            error_event.set()

    if error_event.is_set():
        sys.exit(1)

if __name__ == '__main__':
    main()
