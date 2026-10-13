# Local protocols (verified sources)

Every port, method, and message format below is taken from source code of
existing open-source projects, not assumed. Items marked **unverified on our
device** still need a real-device check before any write command is sent.

## WiZ

Sources:
- pywizlight `discovery.py` and `bulb.py` — https://github.com/sbidy/pywizlight
- WiZ Connected official `wiz-local-control` — https://gitlab.com/wizlighting/wiz-local-control
- homebridge-wiz-lan `network.ts` (broadcast port 38899, discovery rate floor 5 s)

Transport: JSON over **UDP, port 38899**, one datagram per request/response.

### Discovery (broadcast)

pywizlight broadcasts this to `255.255.255.255:38899` (repeated every 1 s
during a ~5 s window) and records every reply whose `result.mac` is present:

```json
{"method":"registration","params":{"phoneMac":"AAAAAAAAAAAA","register":false,"phoneIp":"1.2.3.4","id":"1"}}
```

`register:false` tells the bulb not to keep pushing `syncPilot` to us, so the
probe does not leave state behind. Reply source address = bulb IP.

### Read-only methods (safe)

| Method | Params | Returns |
|---|---|---|
| `getPilot` | none | `state`, `dimming` (10–100 %), `temp` (K), `r,g,b`, `c,w`, `sceneId`, `rssi`, `mac` |
| `getSystemConfig` | none | `mac`, `moduleName`, `fwVersion`, `typeId`, `homeId`, ... |
| `getModelConfig` / `getUserConfig` | none | white ranges (`cctRange`, `extRange`, `whiteRange`) |

### Write method

`setPilot` with any of: `state` (bool), `dimming` (pywizlight clamps to ≥ 1),
`r,g,b` (0–255), `c,w` (0–255), `temp` (Kelvin, pywizlight clamps 1000–10000;
real range comes from `cctRange`), `sceneId`, `speed`. Responses echo
`{"method":"setPilot","result":{"success":true}}`.

UDP is lossy: pywizlight resends at 0, 0.75, 2.25, 5.25 s ... and matches the
reply by `method`.

## CozyLife

Sources:
- Official CozyLife integration — https://github.com/cozylife/hass_cozylife_local_pull
  (`udp_discover.py`, `tcp_client.py`, `const.py`)
- Fixed forks: https://github.com/imatrixcz/hass_cozylife_local_pull,
  https://github.com/yangqian/hass-cozylife
- Issue #38 (TCP 5555 attribute query)

### Discovery (broadcast)

UDP to `255.255.255.255:6095`, sent 3× ~30 ms apart:

```json
{"cmd":0,"pv":0,"sn":"<ms timestamp>","msg":{}}
```

Valid reply: `cmd==0`, `pv==0`, same `sn`, `res==0`, `msg.did` and `msg.pid`
non-empty strings. Example reply documented in `tcp_client.py`:

```json
{"cmd":0,"pv":0,"sn":"1636463553873","msg":{"did":"629168597cb94c4c1d8f","dtp":"02","pid":"e2s64v","mac":"7cb94c4c1d8f","ip":"192.168.123.57","rssi":-33,"sv":"1.0.0","hv":"0.0.1"},"res":0}
```

Some forks report the UDP discovery does not answer on their devices and fall
back to configured IPs. **Unverified on our device.**

### Control (TCP 5555, `\r\n`-framed JSON)

| cmd | Meaning | Request `msg` |
|---|---|---|
| 0 | device info | `{}` |
| 2 | query attributes | `{"attr":[0]}` (0 = all) |
| 3 | set attributes | `{"attr":[1],"data":{"1":0}}` |
| 10 | unsolicited state push | — |

DP ids (`const.py`): `1` switch, `2` work mode, `3` color temp, `4` brightness,
`5` hue, `6` saturation, `13` countdown. Values 0–1000 for temp/brightness,
`65535` for hue/sat means "not in color mode" (from the documented example).
The forks state the official code misreads color scaling — **verify on our
device with a read-only `cmd:2` query before any `cmd:3`.**

No token or key appears in the local protocol. The official integration only
calls the cloud (`api-us.doiting.com`) to fetch product model names by `pid`;
we do not need that for control.

## If research is insufficient

See `odd/tasks/smart-home-local.md` → "Fallback: reverse engineering with REA MCP".
