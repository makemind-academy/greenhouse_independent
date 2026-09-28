# greenhouse-independent

The same server and the same rules run against two installations; the sensor changes model and unit, the control code does not.

Article: [greenhouse-sensor-control-independent](https://makemind.dev/en/build/greenhouse-sensor-control-independent)

## What is here

- `greenhouse_server/` — Dart MCP server (`mcp_server` from pub.dev). It holds the data and the tools and serves the app's pages as `ui://` resources.
- `greenhouse_bus/` — C program standing in for the hardware, built by `verify.sh`.
- `captures/` — screenshots taken from AppPlayer by `verify.py`.
- `verify.py`, `verify.sh` — the check.

## Open it in AppPlayer

Add two server apps, both command `dart`, working directory `greenhouse_server/`, arguments `run bin/server.dart a` and `run bin/server.dart b`: the same server against two installations.

## Verify

```bash
bash verify.sh
```

Needs AppPlayer with the debug MCP on (see `tools/README.md`). The script builds what needs building, drives the player through the screens above, asserts the claim at the top of this file, and writes `captures/`.
