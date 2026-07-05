# XrealSpatial (native)

Native Swift/Metal renderer for spatial displays on the XREAL One. It creates
three off-screen virtual displays, arranges them in space, and renders them as
world-locked panels floating in front of you — a multi-monitor workspace in the
glasses. Head orientation comes from `head_source.py` (the neighbouring `xreal`
library) over UDP.

## Requirements

- XREAL One connected and awake (shows up as the display "One").
- macOS 13+, Xcode / Swift toolchain.
- `head_source.py` running (see the repo root README).

## Run

```bash
# terminal 1 — head tracking (from the repo root)
python3 head_source.py

# terminal 2 — native renderer
cd native
swift run
```

The window auto-selects the "One" display; override with `swift run XrealSpatial --display N`.

## Permissions

Grant these to the **terminal** you run `swift run` from (System Settings >
Privacy & Security), then restart the app:

- **Screen Recording** — required to capture the virtual displays. Without it the
  panels stay flat and the console prints guidance.
- **Accessibility** — required for the window-to-pane hotkeys. Without it head
  tracking and everything else still work; only the hotkeys are inert.

## How to use

1. Start both processes, put on the glasses, look forward and press
   **ctrl+opt+space** to recenter. Three panels sit close together in front of
   you — the Left, Center and Right virtual displays.
2. The three virtual displays are arranged automatically in a row directly
   **above your main screen** (Left | Center | Right), so the layout is
   predictable — no fiddling in System Settings needed.
3. **Put a window on a pane:** focus any app's window and press
   **ctrl+opt+1 / 2 / 3** — it jumps onto the Left / Center / Right pane and
   fills it. This is the main way to work; no blind dragging.
4. **Mouse:** push the cursor up off the top of your main screen to enter the
   Center pane, then move left/right between panes. You see the cursor in the
   glasses once it is on a pane.
5. Optionally set the menu bar's display to a virtual one in
   *System Settings > Displays* so new windows open on a pane by default.

## Controls

Global (work while you are in any app):

| Hotkey | Action |
|--------|--------|
| `ctrl+opt+1/2/3` | send the focused window to the Left / Center / Right pane |
| `ctrl+opt+space` | recenter (define forward / level) |

Window-focused (when the renderer window is active):

| Key | Action |
|-----|--------|
| `up` / `down` | tune pixels-per-degree |
| `x` / `c` / `v` | flip yaw / pitch / roll sign |
| `g` | toggle grid |
| `q` / `esc` | quit |

## How it works

```
Sources/
  CVDShim/               ObjC shim over the private CGVirtualDisplay API
  XrealSpatial/
    main.swift           app, virtual-display creation + arrangement, window,
                         global hotkeys, display selection
    Renderer.swift       MTKViewDelegate: world-locked panels, inline Metal shaders
    ScreenCapture.swift  ScreenCaptureKit -> Metal texture, one stream per display
    WindowMover.swift    Accessibility API: move focused window onto a display
    HeadMath.swift       quaternion + head_angles, thread-safe HeadState
    UDPReceiver.swift    reads head_source packets
```

- Three virtual displays are created (`CGVirtualDisplay`) and arranged with
  `CGConfigureDisplayOrigin`. All panels are virtual, so the render target (the
  glasses) is never captured — no feedback tunnel.
- Each display is captured via ScreenCaptureKit into a Metal texture and drawn
  on its panel, counter-panned by head orientation with roll compensation
  (edges stay world-horizontal).

## Tuning

- `XREAL_VD_COUNT` (0–3): number of virtual displays to create.
- Panel spacing/size and the 46 px/deg default live in `Renderer.swift`.

## Next

Orientation onboarding (auto-resolve signs and scale), configurable panel
layout, and HiDPI virtual displays.
