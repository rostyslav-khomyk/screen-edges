# Screen Edges

Menu-bar Mac app that samples the four edges of the widest display and drives **standard Home Assistant light entities** (Battletron zone lights from the [localtuya](https://github.com/rostyslav-khomyk/localtuya) fork).

No Hyperion. Protocol is the native Home Assistant **REST** API (`POST /api/services/light/turn_on` with `rgb_color`). REST is used instead of the WebSocket so large `/api/states` replies do not hit “Message too long”.

```
Screen Edges  --HA REST-->  light.zone_*  -->  localtuya UDP zones  -->  Battletron strip
```

Those zone lights are normal HA lights, so HomeKit (HomeBridge), Matterbridge, Google Home, and scripts can use the same entities.

## Setup

1. In Home Assistant, create a **long-lived access token** (profile → security).
2. Ensure each Battletron strip has zones configured in localtuya (Add zone / length / edge). Each zone appears as a colour light on the device.
3. Install this app:

```bash
./scripts/install.sh
```

4. Open **Screen Edges → Settings…** from the menu bar:
   - HA URL (e.g. `http://192.168.2.5`)
   - Paste the access token
   - **Connect & refresh lights**
   - Map left / top / right / bottom to the matching zone lights
   - Save, then **Start screen sync**

macOS will ask once for Screen Recording.

### LaunchAgent

`install.sh` installs a LaunchAgent with **`RunAtLoad`** (starts at login) and **`KeepAlive` false** (Quit stays quit; the agent does not relaunch the app).

| Action | Behaviour |
| --- | --- |
| **Pause** sync | Stops capture; leaves zone lights as-is (no `turn_off`, so the next Start does not race strip re-power vs UDP). |
| **Quit** | Turns mapped zone lights off, then exits. |

## Capture notes

ScreenCaptureKit frames are already top-left. The capture path does **not** flip Y when building the RGB buffer — an extra flip swapped top/bottom relative to the physical display. Edge → entity mapping is direct (left/top/right/bottom).

Colours are pushed to HA **one edge at a time** so localtuya’s zone painter does not race parallel `turn_on` calls. `lastSent` is updated only after a successful push.

## Config file

`~/Library/Application Support/ScreenEdges/config.json`

```json
{
  "ha_url": "http://192.168.2.5",
  "ha_token": "…",
  "interval": 0.15,
  "enabled": false,
  "localtuya_only": true,
  "edges": {
    "left": "light.…_zone_1_…",
    "top": "light.…_zone_2_…",
    "right": "light.…_zone_3_…",
    "bottom": "light.…_zone_1_…"
  }
}
```

Older Hyperion configs (`token`, `websocketPort`, `jsonPort`) are ignored; set the HA fields in Settings.

## Test

```bash
swift test
```
