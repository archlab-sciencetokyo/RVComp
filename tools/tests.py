#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# 
# Copyright (c) 2026 Archlab, Science Tokyo
from __future__ import annotations

import difflib
import os
import subprocess
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
LOG_DIR = REPO_ROOT / "log"
DIFF_DIR = LOG_DIR / "diff"
SHOW_STDOUT = os.environ.get("PYTEST_SO_ENABLE", "0") == "1"
FAIL_PREVIEW_LINES = 10


def env_required(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if value:
        return value
    raise pytest.UsageError(f"missing required environment variable: {name}")


def pytest_generate_tests(metafunc: pytest.Metafunc) -> None:
    if "case_name" not in metafunc.fixturenames:
        return
    cases = env_required("RVCOM_TEST_CASES").split()
    if not cases:
        raise pytest.UsageError("RVCOM_TEST_CASES must include at least one test case")
    metafunc.parametrize("case_name", cases)


def run_cmd(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    if SHOW_STDOUT:
        return subprocess.run(
            cmd,
            cwd=cwd,
            text=True,
            check=False,
        )
    return subprocess.run(
        cmd,
        cwd=cwd,
        text=True,
        capture_output=True,
        check=False,
    )


def preview_lines(text: str, max_lines: int = FAIL_PREVIEW_LINES) -> str:
    lines = text.splitlines()
    if not lines:
        return ""
    if len(lines) <= max_lines:
        return "\n".join(lines)
    remain = len(lines) - max_lines
    return "\n".join(lines[:max_lines] + [f"... ({remain} more lines)"])


def fail_with_cmd(prefix: str, cmd: list[str], result: subprocess.CompletedProcess[str]) -> None:
    lines = [
        prefix,
        f"command: {' '.join(cmd)}",
        f"returncode: {result.returncode}",
    ]
    stderr_text = result.stderr or ""
    stdout_text = result.stdout or ""
    if stderr_text:
        lines.append(f"stderr (first {FAIL_PREVIEW_LINES} lines):")
        lines.append(preview_lines(stderr_text))
    if SHOW_STDOUT:
        lines.append("stdout/stderr are streamed because PYTEST_SO_ENABLE=1")
    elif stdout_text and not stderr_text:
        lines.append(f"stdout (first {FAIL_PREVIEW_LINES} lines):")
        lines.append(preview_lines(stdout_text))
    pytest.fail("\n".join(lines))


def strip_spike_header(path: Path, header_lines: int = 5) -> None:
    text = path.read_text()
    lines = text.splitlines(keepends=True)
    path.write_text("".join(lines[header_lines:]))


def write_diff(path_a: Path, path_b: Path, diff_path: Path) -> str:
    a_lines = path_a.read_text().splitlines(keepends=True)
    b_lines = path_b.read_text().splitlines(keepends=True)
    diff_lines = list(
        difflib.unified_diff(
            a_lines,
            b_lines,
            fromfile=str(path_a),
            tofile=str(path_b),
        )
    )
    diff_text = "".join(diff_lines)
    diff_path.write_text(diff_text)
    return diff_text


def test_commit_log_matches_spike(case_name: str) -> None:
    elf_dir = Path(env_required("RVCOM_ELF_DIR"))
    max_cycles = env_required("RVCOM_MAX_CYCLES")
    spike_bin = os.environ.get("RVCOM_SPIKE_BIN", "spike")
    spike_isa = os.environ.get("RVCOM_SPIKE_ISA", "rv32ima_zicntr_zicsr_zifencei")

    LOG_DIR.mkdir(parents=True, exist_ok=True)
    DIFF_DIR.mkdir(parents=True, exist_ok=True)

    elf_file = elf_dir / f"{case_name}.elf"
    mem_file = elf_dir / f"{case_name}.128.hex"
    spike_log = LOG_DIR / f"{case_name}_spike_commit.log"
    rvcom_log = LOG_DIR / f"{case_name}_rvcom_commit.log"
    diff_log = DIFF_DIR / f"{case_name}_commit_log.diff"

    for path in (spike_log, rvcom_log, diff_log):
        if path.exists():
            path.unlink()

    if not elf_file.exists():
        pytest.fail(f"missing elf file: {elf_file}")
    if not mem_file.exists():
        pytest.fail(f"missing mem file: {mem_file}")

    spike_cmd = [
        spike_bin,
        f"--isa={spike_isa}",
        "--log-commits",
        f"--log={spike_log}",
        str(elf_file),
    ]
    spike_result = run_cmd(spike_cmd, REPO_ROOT)
    if spike_result.returncode != 0:
        fail_with_cmd(f"spike execution failed for {case_name}", spike_cmd, spike_result)
    strip_spike_header(spike_log)

    rvcom_cmd = [
        "make",
        "run",
        f"MEM_FILE={mem_file}",
        f"MAX_CYCLES={max_cycles}",
        f"COMMIT_LOG_FILE={rvcom_log.name}",
        "--no-print-directory",
    ]
    rvcom_result = run_cmd(rvcom_cmd, REPO_ROOT)
    if rvcom_result.returncode != 0:
        fail_with_cmd(f"rvcom execution failed for {case_name}", rvcom_cmd, rvcom_result)

    diff_text = write_diff(spike_log, rvcom_log, diff_log)
    if diff_text:
        diff_preview = preview_lines(diff_text)
        pytest.fail(
            f"commit log differs for {case_name}. see {diff_log}\n"
            f"diff preview (first {FAIL_PREVIEW_LINES} lines):\n{diff_preview}"
        )
