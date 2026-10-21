# Screen Edges

Menu-bar Mac app that samples the four edges of the widest display and drives **standard Home Assistant light entities** (Battletron zone lights from the localtuya fork).

No Hyperion. Protocol is the native Home Assistant WebSocket API (`call_service` → `light.turn_on` with `rgb_color`).

```
Screen Edges  --HA WebSocket-->  light.zone_*  -->  localtuya UDP zones  -->  Battletron strip
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
