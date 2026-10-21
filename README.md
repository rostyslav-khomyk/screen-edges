# Screen Edges

A menu-bar Mac app that samples the full four edges of the widest display and streams spatial colors to the Battletron zones in the [LocalTuya fork](https://github.com/rostyslav-khomyk/localtuya). Requires LocalTuya 2026.10.2 and HA Core 2026.10.2 or newer. The release candidate is tested against HA 2026.10.2.

```
Screen capture → 80 samples → authenticated Hyperion WebSocket → HA mapping
                                                              ↓
HA zone lights ──────────────────────────────────── shared UDP painter → strips
```

The app serves the authenticated Hyperion JSON LED-stream subset, with 20 samples per edge in left/top/right/bottom order. HA pulls those frames and resamples them into the **20 logical sections per strip** verified with the hardware tests. These are spatial groups, not individually addressable visible emitters. Manual HA lights and screen streaming share the existing unicast UDP engine.

## Setup

1. Configure Battletron zones and their physical lengths in LocalTuya. Both strips must belong to the same LocalTuya integration entry.
2. Use an administrator's HA long-lived access token (profile → security).
3. Install the validated app bundle. For a development checkout, `./scripts/install.sh` builds and installs the app and LaunchAgent; this changes the running app. Do not use the old `build-pkg.sh` package for this release.
4. Open **Screen Edges → Settings…**, enter the direct LAN HA URL and token, then connect. HA must be able to connect back to the Mac on the stream port (default 8090). A reverse proxy or remote HA URL can hide the Mac's source address; use the direct LAN connection.
5. Each HA zone has its own edge selector and **Reverse** toggle. Multiple zones and strips can use the same edge. Unmapped sections on a participating strip are black.
6. Save, grant Screen Recording when macOS asks, then start sync.

Zone order follows the controller end of the strip. Left/right edge samples run top to bottom; top/bottom samples run left to right. Reverse each destination as necessary for physical wiring. The inset monitor strip's 27/57/27 cm lengths allocate 5/10/5 sections; each section set samples the **full** corresponding screen edge. Physical strip dimensions do not crop the screen.

The desk can keep its existing single bottom zone until the actual 1d/2d/3d lengths are measured. Then map them to left/bottom/right. Use the monitor's actual approximately 81 cm screen span for placement, rather than the inset 57 cm top strip run.

## Ownership and recovery

Starting sync acquires the selected strips only after HA receives a valid frame. Zone entities stay registered and keep their saved colors, brightness and on/off state. Manual changes to a participating strip return “Screen sync is active”; pause before changing its lights or zone layout.

Pause and Quit release ownership and restore manual output, including zones previously off. A disconnected source, malformed frame, or five seconds without a valid frame also releases ownership. The app retries after HA becomes available again. An integration unload stops the painter without briefly restoring output into closing devices.

The LaunchAgent starts at login; Quit stays quit. The config remains at `~/Library/Application Support/ScreenEdges/config.json`, is saved with owner-only permissions, and migrates existing `edges` mappings automatically. New `mappings` support repeated edges and per-zone reversal. Never distribute this file: it contains access tokens.

## Local validation

```bash
swift test
swift build -c release
```

`screen-edges-stream-fixture` runs the production WebSocket server with deterministic colors, without capturing a screen or sending UDP. The LocalTuya tests use it with a real isolated HA HTTP/auth server and a recorded output engine. See LocalTuya's `docs/GRANULAR_SYNC_IMPLEMENTATION.md` for the cross-language tests and deployment gate.
