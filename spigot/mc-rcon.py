#!/usr/bin/env python3
"""mc-rcon.py — send one console command to the local Minecraft server via RCON.

Usage: mc-rcon.py <command...>
Reads port and password from /server/data/cfg/server.properties (set up by
entrypoint.sh). Prints the server's reply. Exit code 2 if the server is not
reachable (e.g. stopped or still starting), 1 on other errors.
"""
import socket
import struct
import sys

PROPS = "/server/data/cfg/server.properties"


def props():
    out = {}
    with open(PROPS, encoding="utf-8") as f:
        for line in f:
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.rstrip("\n").split("=", 1)
                out[k.strip()] = v.strip()
    return out


def packet(req_id, kind, body):
    data = struct.pack("<ii", req_id, kind) + body.encode("utf-8") + b"\x00\x00"
    return struct.pack("<i", len(data)) + data


def read_packet(sock):
    def recv_exact(n):
        buf = b""
        while len(buf) < n:
            chunk = sock.recv(n - len(buf))
            if not chunk:
                raise ConnectionError("connection closed")
            buf += chunk
        return buf

    (length,) = struct.unpack("<i", recv_exact(4))
    data = recv_exact(length)
    req_id, kind = struct.unpack("<ii", data[:8])
    return req_id, kind, data[8:-2].decode("utf-8", "replace")


def main():
    if len(sys.argv) < 2:
        print("Usage: mc-rcon.py <command>")
        return 1
    p = props()
    if p.get("enable-rcon") != "true":
        print("RCON is not enabled.")
        return 2
    port = int(p.get("rcon.port", "25575"))
    password = p.get("rcon.password", "")
    try:
        sock = socket.create_connection(("127.0.0.1", port), timeout=5)
    except OSError:
        print("Server is not reachable (stopped or still starting).")
        return 2
    with sock:
        sock.sendall(packet(1, 3, password))
        req_id, _, _ = read_packet(sock)
        if req_id == -1:
            print("RCON authentication failed.")
            return 1
        sock.sendall(packet(2, 2, " ".join(sys.argv[1:])))
        _, _, body = read_packet(sock)
        print(body)
    return 0


if __name__ == "__main__":
    sys.exit(main())
