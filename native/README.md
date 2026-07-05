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

## Virtual displays

On launch the app creates two off-screen **virtual displays** via the private
`CGVirtualDisplay` API (`CVDShim`, an Objective-C shim) and assigns them to the
left and right panels; the center panel shows your real main display. Each is
captured via ScreenCaptureKit into a Metal texture (`ScreenCapture.swift`).

The virtual displays appear in *System Settings > Displays* as "XREAL Left" and
"XREAL Right". Arrange them there, then drag windows/apps onto them — they are
off-screen on the Mac but visible in the glasses panels. They are destroyed when
the app quits. Set `XREAL_VD_COUNT=0` to disable them (capture main display only).

Requires **Screen Recording** permission for the terminal running `swift run`
(System Settings > Privacy & Security > Screen Recording). Without it the app
still runs; panels just stay flat and the console prints guidance.

If the captured panel appears vertically flipped, swap the V texture
coordinates in `Renderer.build` (tl/bl ↔ 0/1).

## Next

Create off-screen virtual displays (CGVirtualDisplay) and capture each onto its
own panel, then add the orientation onboarding step.
