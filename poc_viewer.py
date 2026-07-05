#!/usr/bin/env python3
"""
Latency proof-of-concept viewer for XREAL spatial displays.

Renders a WORLD-LOCKED scene (grid + three placeholder "monitor" panels at
-40°/0°/+40° azimuth) fullscreen on the glasses. It counter-pans the scene by
the head orientation streamed from head_source.py, so the panels appear to
stay fixed in space while you look around — the multi-monitor illusion.

Purpose: FEEL whether the head-tracked pan is fast/stable enough (motion-to-
photon latency) before investing in the native renderer.

    # terminal 1
    python3 head_source.py
    # terminal 2  (glasses are usually the last display)
    python3 poc_viewer.py --display 1
    #   or, to test on the laptop screen first:
    python3 poc_viewer.py --windowed

Keys:  space = recenter (this = forward/level)   [ / ] = tune px-per-degree
       x = flip yaw   c = flip pitch   v = flip roll   g = grid   q/esc = quit

The flip keys are the seed of the final app's onboarding step: they resolve the
per-mount sign ambiguity so left/right/up/down map the right way.
"""
import argparse
import math
import os
import socket
import struct
import sys
import time

import pygame

# reuse the mounting-correct decomposition from the neighbouring xreal lib
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "xreal"))
from xreal import head_angles  # noqa: E402

PACKET = struct.Struct("<dffff")   # (wall_time, qw, qx, qy, qz)

# XREAL One ~ 50° diagonal FOV -> ~44 px/deg at 1080p. Tunable live with [ ].
DEFAULT_PPD = 44.0

PANELS = [   # (azimuth°, elevation°, width°, height°, label)
    (-40, 0, 30, 17, "Display 1"),
    (0,   0, 30, 17, "Display 2"),
    (40,  0, 30, 17, "Display 3"),
]


class HeadState:
    def __init__(self):
        self.q = None             # latest quaternion (w,x,y,z)
        self.q_ref = None         # recenter reference
        self.stamp = 0.0
        self.az = self.el = self.roll = 0.0
        # per-mount sign corrections (resolved via the flip keys / onboarding)
        self.sx = self.sy = self.sr = 1.0

    def apply(self, t, w, x, y, z):
        self.stamp = t
        self.q = (w, x, y, z)
        if self.q_ref is None:
            self.q_ref = self.q
        az, el, roll = head_angles(self.q, self.q_ref)
        self.az, self.el, self.roll = az * self.sx, el * self.sy, roll * self.sr

    def recenter(self):
        if self.q is not None:
            self.q_ref = self.q

    @property
    def rollr(self):
        return math.radians(self.roll)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=51234)
    ap.add_argument("--display", type=int, default=None,
                    help="display index (default: last = usually the glasses)")
    ap.add_argument("--windowed", action="store_true", help="test in a window")
    ap.add_argument("--ppd", type=float, default=DEFAULT_PPD)
    args = ap.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", args.port))
    sock.setblocking(False)

    pygame.init()
    pygame.mouse.set_visible(False)
    sizes = pygame.display.get_desktop_sizes()
    disp = args.display if args.display is not None else len(sizes) - 1
    disp = max(0, min(disp, len(sizes) - 1))
    if args.windowed:
        screen = pygame.display.set_mode((1280, 720))
    else:
        screen = pygame.display.set_mode(sizes[disp], pygame.FULLSCREEN, display=disp)
    pygame.display.set_caption("xreal-spatial PoC")
    W, H = screen.get_size()
    cx, cy = W / 2, H / 2
    font = pygame.font.SysFont("Menlo", 22)
    small = pygame.font.SysFont("Menlo", 16)
    clock = pygame.time.Clock()

    head = HeadState()
    ppd = args.ppd
    show_grid = True

    BG = (12, 12, 16)
    GRID = (40, 44, 54)
    PANEL = (60, 120, 210)
    PANEL_HL = (90, 200, 140)
    CROSS = (230, 90, 90)
    TEXT = (210, 214, 224)

    def project(az, el):
        """World (azimuth, elevation) in degrees -> screen pixel, with roll."""
        dx = (az - head.az) * ppd
        dy = -(el - head.el) * ppd
        r = -head.rollr
        c, s = math.cos(r), math.sin(r)
        return (cx + dx * c - dy * s, cy + dx * s + dy * c)

    running = True
    fps_ema = 0.0
    while running:
        for e in pygame.event.get():
            if e.type == pygame.QUIT:
                running = False
            elif e.type == pygame.KEYDOWN:
                if e.key in (pygame.K_q, pygame.K_ESCAPE):
                    running = False
                elif e.key == pygame.K_SPACE:
                    head.recenter()
                elif e.key == pygame.K_LEFTBRACKET:
                    ppd = max(10.0, ppd - 1.0)
                elif e.key == pygame.K_RIGHTBRACKET:
                    ppd += 1.0
                elif e.key == pygame.K_x:
                    head.sx *= -1
                elif e.key == pygame.K_c:
                    head.sy *= -1
                elif e.key == pygame.K_v:
                    head.sr *= -1
                elif e.key == pygame.K_g:
                    show_grid = not show_grid

        # drain UDP to the newest packet
        newest = None
        try:
            while True:
                newest = sock.recv(PACKET.size)
        except BlockingIOError:
            pass
        if newest and len(newest) == PACKET.size:
            head.apply(*PACKET.unpack(newest))

        screen.fill(BG)

        if show_grid:
            a0, a1 = head.az - 60, head.az + 60
            e0, e1 = head.el - 40, head.el + 40
            for az in range(int(a0 // 5 * 5), int(a1) + 5, 5):
                pygame.draw.line(screen, GRID, project(az, e0), project(az, e1), 1)
            for el in range(int(e0 // 5 * 5), int(e1) + 5, 5):
                pygame.draw.line(screen, GRID, project(a0, el), project(a1, el), 1)

        for az, el, w, h, label in PANELS:
            corners = [project(az - w / 2, el + h / 2), project(az + w / 2, el + h / 2),
                       project(az + w / 2, el - h / 2), project(az - w / 2, el - h / 2)]
            centered = abs(az - head.az) < w / 2
            col = PANEL_HL if centered else PANEL
            pygame.draw.polygon(screen, col, corners, 3)
            lbl = font.render(label, True, col)
            c = project(az, el)
            screen.blit(lbl, (c[0] - lbl.get_width() / 2, c[1] - lbl.get_height() / 2))

        pygame.draw.line(screen, CROSS, (cx - 16, cy), (cx + 16, cy), 2)
        pygame.draw.line(screen, CROSS, (cx, cy - 16), (cx, cy + 16), 2)

        fps = clock.get_fps()
        fps_ema = fps if fps_ema == 0 else 0.9 * fps_ema + 0.1 * fps
        age_ms = (time.time() - head.stamp) * 1000.0 if head.stamp else -1
        signs = f"yaw{'+' if head.sx > 0 else '-'} pitch{'+' if head.sy > 0 else '-'} roll{'+' if head.sr > 0 else '-'}"
        hud = [
            f"az {head.az:+6.1f}  el {head.el:+6.1f}  roll {head.roll:+6.1f}",
            f"{fps_ema:4.0f} fps   IMU-age {age_ms:4.0f} ms   ppd {ppd:.0f}   [{signs}]",
            "space=recenter  [ ]=ppd  x/c/v=flip yaw/pitch/roll  g=grid  q=quit",
        ]
        if not head.stamp:
            hud.insert(0, "WAITING for head_source ...")
        for i, line in enumerate(hud):
            screen.blit(small.render(line, True, TEXT), (16, 14 + i * 20))

        pygame.display.flip()
        clock.tick(120)

    pygame.quit()


if __name__ == "__main__":
    main()
