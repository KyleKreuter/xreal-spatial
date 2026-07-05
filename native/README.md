# XrealSpatial (native)

Native Swift/Metal renderer — the first version of the real spatial-display app.
Renders a world-locked scene (grid + three placeholder monitor panels) fullscreen
on the XREAL One, consuming head orientation from `head_source.py` over UDP.

This is the lower-latency successor to the Python PoC. It ports the validated
head math (`xreal.head_angles`, level-lock, roll compensation, ppd 46) to Swift.

## Run

```bash
# terminal 1 — head tracking (from the repo root)
python3 head_source.py

# terminal 2 — native renderer
cd native
swift run                 # or: swift run XrealSpatial --display 1
```

The app auto-selects the 1920x1080 XREAL One display; override with `--display N`.

### Controls

| Key | Action |
|-----|--------|
| `space` | recenter (forward / level) |
| `up` / `down` | tune pixels-per-degree |
| `x` / `c` / `v` | flip yaw / pitch / roll sign |
| `g` | toggle grid |
| `q` / `esc` | quit |

## Structure

```
Sources/XrealSpatial/
  main.swift          NSApplication, window on the glasses display, key handling
  Renderer.swift      MTKViewDelegate: builds geometry, inline Metal shaders
  HeadMath.swift      quaternion + head_angles port, thread-safe HeadState
  UDPReceiver.swift   background socket reader for head_source packets
```

## Next

Replace the placeholder panels with captured virtual displays (CGVirtualDisplay
+ ScreenCaptureKit), then add the orientation onboarding step.
