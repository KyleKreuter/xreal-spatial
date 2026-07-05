# xreal-spatial

Spatial / world-locked displays for the [XREAL One](https://eu.shop.xreal.com/en-de/products/xreal-one) — turning the single head-locked screen into multiple app windows that stay fixed in space, like Apple Vision Pro.

This repository starts with a **latency proof-of-concept** in Python. The goal is to feel whether head-tracked counter-panning is fast and stable enough (motion-to-photon latency) before building the native Swift/Metal renderer.

Head tracking comes from the neighbouring [`xreal`](../xreal) library.

## Architecture

```
head_source.py   xreal IMU -> pitch/yaw/roll -> UDP  (reused by the native renderer)
        │  udp://127.0.0.1:51234   struct '<dfff'
        ▼
poc_viewer.py    pygame: world-locked grid + placeholder monitor panels,
                 counter-panned by head orientation, fullscreen on the glasses
```

## Run

Install the one dependency:

```bash
pip install -r requirements.txt
```

Then, in two terminals:

```bash
python3 head_source.py                 # streams head orientation
python3 poc_viewer.py --display 1      # renders on the glasses (usually display 1)
```

To try it on the laptop screen first, use `poc_viewer.py --windowed`.

### Controls

| Key | Action |
|-----|--------|
| `space` | recenter (define current pose as forward / level) |
| `[` / `]` | tune pixels-per-degree until the world locks |
| `g` | toggle grid |
| `q` / `esc` | quit |

## What to look for

Wear the glasses, run both processes, press `space` while looking forward, then
turn your head. The three panels should stay put in space — you look from one to
the next. Judge: does the scene feel **locked**, or does it swim/lag? Tune
`[` / `]` so a world point stays fixed as you rotate. The HUD shows FPS and IMU
data age (ms).

## Orientation onboarding (required for the native app)

Head-mount orientation has per-fit ambiguities (which way is forward/level, and
the sign of each axis). The PoC exposes these as manual keys (`space`, `x`/`c`/`v`);
the final Mac app must resolve them automatically via a short first-run step:

1. **Center** — "Look straight ahead at the marker" → captures the reference
   pose (`q_ref`). Removes the azimuth/elevation offset.
2. **Yaw sign** — "Turn your head right" → auto-flip yaw if it moves the wrong way.
3. **Pitch sign** — "Nod down" → auto-flip pitch likewise.
4. **Roll sign** — "Tilt your head right" → auto-flip roll likewise.
5. **Scale (px/deg)** — "Look from the left marker to the right marker" → derive
   pixels-per-degree from the known angular separation, auto-tuning the FOV.

Result: correct, per-user world-lock with zero manual fiddling. Persist the
resolved center/signs/scale so it is a one-time step.

## Next

If the latency feels right, the panels become captured virtual displays and the
renderer moves to native Swift/Metal + ScreenCaptureKit for the real thing.
The orientation onboarding above is a first-class part of that app.
