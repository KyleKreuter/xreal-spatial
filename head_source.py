#!/usr/bin/env python3
"""
Head-orientation source for the spatial-display PoC.

Uses the neighbouring `xreal` library to read the glasses' IMU, fuses it to
pitch/yaw/roll, and streams each update as a small UDP packet to the viewer
(and, later, to the native Swift/Metal renderer — same wire format).

    python3 head_source.py [--host 127.0.0.1] [--port 51234]

Packet: struct '<dffff' = (wall_time, qw, qx, qy, qz)
The quaternion lets the receiver do mounting-correct decomposition itself
(xreal.head_angles). wall_time lets it measure end-to-end data age (latency).
"""
import argparse
import os
import socket
import struct
import sys
import time

# import the sibling `xreal` package (neighbouring repo)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "xreal"))
from xreal import XrealOne, HeadTracker, DeviceError  # noqa: E402

PACKET = struct.Struct("<dffff")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=51234)
    args = ap.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    addr = (args.host, args.port)
    tracker = HeadTracker()

    print(f"Head-Source -> udp://{args.host}:{args.port}  (Ctrl+C to stop)")
    try:
        with XrealOne() as dev:
            n = 0
            for ori in tracker.stream(dev):
                w, x, y, z = ori.quat
                sock.sendto(PACKET.pack(time.time(), w, x, y, z), addr)
                n += 1
                if n % 500 == 0:
                    print(f"\r{n:>7} pkts  quat[{w:+.2f} {x:+.2f} {y:+.2f} {z:+.2f}]  "
                          f"bias{tracker.bias_dps:4.2f}°/s "
                          f"{'STILL' if ori.is_still else '     '}",
                          end="", flush=True)
    except DeviceError as e:
        print("NO-GO:", e)
    except KeyboardInterrupt:
        print("\nBye.")


if __name__ == "__main__":
    main()
