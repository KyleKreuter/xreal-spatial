#!/usr/bin/env python3
"""
Head-orientation source for the spatial-display PoC.

Uses the neighbouring `xreal` library to read the glasses' IMU, fuses it to
pitch/yaw/roll, and streams each update as a small UDP packet to the viewer
(and, later, to the native Swift/Metal renderer — same wire format).

    python3 head_source.py [--host 127.0.0.1] [--port 51234]

Packet: struct '<dfff' = (wall_time, pitch_deg, yaw_deg, roll_deg)
The wall_time lets the receiver measure end-to-end data age (latency).
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

PACKET = struct.Struct("<dfff")


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
                sock.sendto(PACKET.pack(time.time(), ori.pitch, ori.yaw, ori.roll), addr)
                n += 1
                if n % 500 == 0:
                    print(f"\r{n:>7} pkts  P{ori.pitch:+6.1f} Y{ori.yaw:+6.1f} "
                          f"R{ori.roll:+6.1f}  bias{tracker.bias_dps:4.2f}°/s "
                          f"{'STILL' if ori.is_still else '     '}",
                          end="", flush=True)
    except DeviceError as e:
        print("NO-GO:", e)
    except KeyboardInterrupt:
        print("\nBye.")


if __name__ == "__main__":
    main()
