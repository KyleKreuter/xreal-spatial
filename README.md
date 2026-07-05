# xreal-spatial-poc

A proof-of-concept **spatial multi-monitor desktop** for the
[XREAL One](https://eu.shop.xreal.com/en-de/products/xreal-one). It turns the
glasses' single head-locked screen into **three world-locked virtual monitors**
floating in space — look around to switch between them, drop windows onto them
with a hotkey.

Head tracking comes from the [`xreal`](../xreal) library (a sibling repo).

## What it does today

- Creates **three off-screen virtual displays** (private `CGVirtualDisplay` API)
  and arranges them in a row above the main screen.
- Renders them as **world-locked panels** in the glasses via Metal — they stay
  fixed in space as you turn your head; edges stay level (roll-compensated).
- Captures each display with **ScreenCaptureKit** into a Metal texture at ~120 fps.
- **Global hotkeys** to send the focused window to a pane and to recenter.
- Head latency hidden by orientation **prediction**; world-lock calibrated to
  the One (46 px/deg).

## Layout

| Path | What |
|------|------|
| `native/` | The real app — Swift/Metal renderer, virtual displays, capture, hotkeys. **Start here.** |
| `head_source.py` | Streams head orientation from the glasses over UDP (uses the `xreal` lib). |
| `poc_viewer.py` | The original Python/pygame latency proof-of-concept. |

## Quick start

```bash
# terminal 1 — head tracking
python3 head_source.py

# terminal 2 — native spatial renderer
cd native
swift run
```

Put on the glasses, press **ctrl+opt+space** to recenter, then send windows to
panes with **ctrl+opt+1 / 2 / 3**. Full setup, permissions and controls are in
[`native/README.md`](native/README.md).

## How it works

```
glasses IMU ──▶ head_source.py ──UDP──▶ native renderer ──▶ world-locked panels
                (xreal lib, fused           (Metal)          on the glasses
                 + predicted)                  ▲
CGVirtualDisplay ×3 ──▶ ScreenCaptureKit ──────┘
```

The glasses' display is physically head-locked, so the renderer counter-rotates
its content by the measured head orientation to make the panels appear fixed in
the world.

## Status

Working proof-of-concept. Known rough edges:

- Panel layout (spacing, size) and virtual-display resolution are fixed
  (1920×1080, non-HiDPI).
- Axis-sign calibration is baked in for one head mount; a first-run
  **orientation onboarding** to auto-resolve it is the next step.
- A small residual yaw drift is inherent (the One has no magnetometer); recenter
  with a hotkey.

## Requirements

- XREAL One, macOS 13+, Swift toolchain, Python 3.8+.
- Screen Recording permission (capture) and Accessibility permission (window
  hotkeys) for the launching terminal — see `native/README.md`.
