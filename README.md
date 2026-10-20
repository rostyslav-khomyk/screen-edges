# screen-edges

Mac screen-edge grabber. It publishes the left, top, right, and bottom colors of the widest display using the [Hyperion NG JSON API](https://api.hyperion-project.org/).

Home Assistant, and the localtuya fork in this setup, connect as Hyperion clients. The token is a bearer secret. Several clients can subscribe at once, so two LED strips can follow the same screen.

## LED order

| Index | Edge |
| --- | --- |
| 0 | left |
| 1 | top |
| 2 | right |
| 3 | bottom |

`serverinfo` lists those names. After `ledcolors` / `ledstream-start`, updates arrive as `ledcolors-ledstream-update` about 8 times a second.

## Ports

- WebSocket `8090`. Send `{"command":"authorize","subcommand":"login","token":"<token>"}`.
- Newline-delimited JSON on TCP `19444`, same commands. This is the classic Hyperion JSON port.

## Install

The service has to run in your logged-in session. Screen capture is not available to a root daemon.

```bash
./scripts/install.sh
./scripts/uninstall.sh
```

`install.sh` builds a release app, writes `~/Library/Application Support/ScreenEdges/config.json` with a token, and loads a LaunchAgent for the logged-in session.

The first launch needs Screen Recording permission for **Screen Edges**. System Settings, Privacy & Security, Screen Recording. The listeners stay up and retry the capture until that permission is on.

A package is optional:

```bash
./scripts/build-pkg.sh
```

Install `ScreenEdges.pkg`, then run `/usr/local/share/screen-edges/install.sh` so the LaunchAgent and token are created for your user.

## Test

```bash
swift test
```

## Check the stream

```bash
TOKEN=$(python3 -c 'import json; print(json.load(open("/Users/'"$USER"'/Library/Application Support/ScreenEdges/config.json"))["token"])')
printf '%s\n' "{\"command\":\"authorize\",\"subcommand\":\"login\",\"token\":\"$TOKEN\",\"tan\":1}" \
  '{"command":"ledcolors","subcommand":"ledstream-start","tan":2}' \
  | nc 127.0.0.1 19444
```
