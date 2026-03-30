#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
#
# Copyright (c) 2026 Archlab, Science Tokyo

from __future__ import annotations

import argparse
import asyncio
import struct
import time
from dataclasses import dataclass, field
from pathlib import Path

from aiohttp import WSMsgType, web

UDP_MAGIC = 0x52564350  # "RVCP"
WS_MAGIC = 0x52564350   # "RVCP"

UDP_HDR = struct.Struct("!IBBHIHHHHHH")
WS_HDR = struct.Struct("<IIHHI")


@dataclass(frozen=True)
class UdpChunk:
    seq: int
    width: int
    height: int
    chunk_idx: int
    chunk_count: int
    payload: bytes


@dataclass
class FrameAssembly:
    width: int
    height: int
    chunk_count: int
    chunks: dict[int, bytes] = field(default_factory=dict)
    created_at: float = field(default_factory=time.monotonic)


def parse_udp_chunk(data: bytes) -> UdpChunk | None:
    if len(data) < UDP_HDR.size:
        return None

    (
        magic,
        version,
        _reserved0,
        header_bytes,
        seq,
        width,
        height,
        chunk_idx,
        chunk_count,
        payload_len,
        _reserved1,
    ) = UDP_HDR.unpack_from(data)

    if magic != UDP_MAGIC or version != 1:
        return None
    if header_bytes < UDP_HDR.size:
        return None
    if chunk_count == 0 or chunk_idx >= chunk_count:
        return None
    if len(data) < header_bytes + payload_len:
        return None

    return UdpChunk(
        seq=seq,
        width=width,
        height=height,
        chunk_idx=chunk_idx,
        chunk_count=chunk_count,
        payload=data[header_bytes:header_bytes + payload_len],
    )


def build_ws_frame(seq: int, width: int, height: int, frame: bytes) -> bytes:
    return WS_HDR.pack(WS_MAGIC, seq, width, height, len(frame)) + frame


class CameraRelay:
    def __init__(self) -> None:
        self._assemblies: dict[int, FrameAssembly] = {}
        self._clients: set[web.WebSocketResponse] = set()
        self._lock = asyncio.Lock()

    async def register_ws(self, ws: web.WebSocketResponse) -> None:
        async with self._lock:
            self._clients.add(ws)

    async def unregister_ws(self, ws: web.WebSocketResponse) -> None:
        async with self._lock:
            self._clients.discard(ws)

    async def on_datagram(self, data: bytes) -> None:
        chunk = parse_udp_chunk(data)
        if chunk is None:
            return

        assembly = self._get_or_create_assembly(chunk)
        assembly.chunks.setdefault(chunk.chunk_idx, chunk.payload)
        self._cleanup_old(chunk.seq)

        frame = self._finalize_frame(chunk.seq)
        if frame is None:
            return

        await self._broadcast_frame(chunk.seq, assembly.width, assembly.height, frame)

    def _get_or_create_assembly(self, chunk: UdpChunk) -> FrameAssembly:
        assembly = self._assemblies.get(chunk.seq)
        if assembly is None or (
            assembly.width != chunk.width
            or assembly.height != chunk.height
            or assembly.chunk_count != chunk.chunk_count
        ):
            assembly = FrameAssembly(
                width=chunk.width,
                height=chunk.height,
                chunk_count=chunk.chunk_count,
            )
            self._assemblies[chunk.seq] = assembly
        return assembly

    def _finalize_frame(self, seq: int) -> bytes | None:
        assembly = self._assemblies.get(seq)
        if assembly is None or len(assembly.chunks) != assembly.chunk_count:
            return None

        parts = []
        for idx in range(assembly.chunk_count):
            chunk = assembly.chunks.get(idx)
            if chunk is None:
                return None
            parts.append(chunk)

        del self._assemblies[seq]
        return b"".join(parts)

    def _cleanup_old(self, newest_seq: int) -> None:
        deadline = time.monotonic() - 1.0
        stale = []
        for seq, assembly in self._assemblies.items():
            if seq + 8 < newest_seq or assembly.created_at < deadline:
                stale.append(seq)
        for seq in stale:
            self._assemblies.pop(seq, None)

    async def _broadcast_frame(self, seq: int, width: int, height: int, frame: bytes) -> None:
        payload = build_ws_frame(seq, width, height, frame)

        async with self._lock:
            clients = list(self._clients)

        dead: list[web.WebSocketResponse] = []
        for ws in clients:
            try:
                await ws.send_bytes(payload)
            except Exception:
                dead.append(ws)

        if dead:
            async with self._lock:
                for ws in dead:
                    self._clients.discard(ws)


class UdpProtocol(asyncio.DatagramProtocol):
    def __init__(self, relay: CameraRelay) -> None:
        self._relay = relay

    def datagram_received(self, data: bytes, addr) -> None:  # type: ignore[override]
        asyncio.create_task(self._relay.on_datagram(data))


async def ws_handler(request: web.Request) -> web.WebSocketResponse:
    relay: CameraRelay = request.app["relay"]

    ws = web.WebSocketResponse(heartbeat=20.0)
    await ws.prepare(request)
    await relay.register_ws(ws)

    try:
        async for msg in ws:
            if msg.type == WSMsgType.ERROR:
                break
    finally:
        await relay.unregister_ws(ws)
    return ws


async def static_file_handler(request: web.Request, filename: str) -> web.FileResponse:
    base_dir: Path = request.app["base_dir"]
    return web.FileResponse(base_dir / "static" / filename)


async def index_handler(request: web.Request) -> web.FileResponse:
    return await static_file_handler(request, "index.html")


async def licenses_handler(request: web.Request) -> web.FileResponse:
    return await static_file_handler(request, "licenses.html")


async def start_udp(app: web.Application) -> None:
    loop = asyncio.get_running_loop()
    relay: CameraRelay = app["relay"]
    host = app["udp_host"]
    port = app["udp_port"]
    transport, _ = await loop.create_datagram_endpoint(
        lambda: UdpProtocol(relay),
        local_addr=(host, port),
    )
    app["udp_transport"] = transport
    print(f"[relay] UDP listening on {host}:{port}")


async def stop_udp(app: web.Application) -> None:
    transport = app.get("udp_transport")
    if transport is not None:
        transport.close()


def build_app(base_dir: Path, udp_host: str, udp_port: int) -> web.Application:
    app = web.Application()
    app["relay"] = CameraRelay()
    app["base_dir"] = base_dir
    app["udp_host"] = udp_host
    app["udp_port"] = udp_port
    app.router.add_get("/", index_handler)
    app.router.add_get("/licenses", licenses_handler)
    app.router.add_get("/ws", ws_handler)
    app.router.add_static("/static", base_dir / "static")
    app.on_startup.append(start_udp)
    app.on_cleanup.append(stop_udp)
    return app


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="RVComp camera relay")
    parser.add_argument("--udp-host", default="0.0.0.0", help="UDP bind host")
    parser.add_argument("--udp-port", type=int, default=5000, help="UDP bind port")
    parser.add_argument("--ws-host", default="0.0.0.0", help="HTTP/WS bind host")
    parser.add_argument("--ws-port", type=int, default=8000, help="HTTP/WS bind port")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    base_dir = Path(__file__).resolve().parent
    app = build_app(base_dir, args.udp_host, args.udp_port)
    print(f"[relay] HTTP/WS listening on {args.ws_host}:{args.ws_port}")
    web.run_app(app, host=args.ws_host, port=args.ws_port)


if __name__ == "__main__":
    main()
