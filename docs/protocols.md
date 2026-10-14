# Local protocols (verified sources)

Every port, method, and message format below is taken from source code of
existing open-source projects, not assumed. Items marked **unverified on our
device** still need a real-device check before any write command is sent.

## WiZ

Sources:
- pywizlight `discovery.py` — https://github.com/sbidy/pywizlight
- pywizlight [`bulb.py`](https://raw.githubusercontent.com/sbidy/pywizlight/master/pywizlight/bulb.py)
  (`PilotBuilder`, `_set_rgbww`, `_set_rgb`, configuration queries)
- pywizlight [`bulblibrary.py`](https://raw.githubusercontent.com/sbidy/pywizlight/master/pywizlight/bulblibrary.py)
  (`BulbType.from_data`, module classification and `KelvinRange`)
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
| `getPilot` | none | `state`, `dimming` (%), `temp` (K), `r,g,b`, `c,w`, `sceneId`, `rssi`, `mac` |
| `getSystemConfig` | none | `mac`, `moduleName`, `fwVersion`, `typeId`, `homeId`, ... |
| `getModelConfig` / `getUserConfig` | none | white ranges (`cctRange`, `extRange`, `whiteRange`) |

### Driver connection and capabilities

`WiZDevice.connect` performs only `getSystemConfig` and `getModelConfig`; it
queries `getUserConfig` only when the model response has no usable temperature
range. It does not register for pushes, broadcast, or write light state.

- Power and percentage brightness use the verified WiZ pilot protocol.
- RGB is advertised only when the second underscore-separated component of the
  reported `moduleName` contains `RGB` (`BulbType.from_data`); discovery metadata
  alone never enables RGB.
- Temperature uses the minimum and maximum of the first valid advertised range
  in `cctRange`, `extRange`, `whiteRange` order. Ranges must contain at least two
  positive integers with distinct endpoints. Missing, malformed, or timed-out
  range replies trigger the user-config fallback; if it also has no usable range,
  temperature is unsupported. No guessed Kelvin defaults are used.
- Failure to read system configuration aborts connection. Transport errors
  propagate; optional range-query timeouts leave temperature unsupported.

Parent-observed read-only evidence: `ESP01_SHRGB1C_31`, firmware `1.35.0`,
`drvConf:[33,1]`; model `cctRange:[2200,2699,6500,6500]`, `nowc:1`, `wcr:33`;
user `minDimming:0`; pilot `state:true`, `temp:3714`, `dimming:83`, `sceneId:0`.
These are fixtures/evidence, not source defaults. Real setter readback remains
an integration check performed by the parent, not by socket-free driver tests.

### Absolute setters (validated before sending)

Every write is a JSON `setPilot` request (one datagram per transmission) to the
discovered address on UDP 38899. The driver turns the light on for nonzero brightness,
RGB, and Kelvin commands by sending explicit `state:true`.

| Operation | Exact `params` example | Accepted values |
|---|---|---|
| On / off | `{"state":true}` / `{"state":false}` | Boolean state |
| Brightness | `{"state":true,"dimming":50}` | 1–100 percent; 0 maps to OFF without sending `dimming:0` |
| Direct RGB | `{"state":true,"r":255,"g":0,"b":0,"c":0,"w":0}` | Every RGB channel 0–255; RGB capability required |
| Temperature | `{"state":true,"temp":3714}` | Kelvin inside this device's advertised inclusive range |

Direct RGB deliberately follows `_set_rgbww` channel semantics, clearing cold
and warm white with `c:0,w:0`. It does **not** copy `_set_rgb`'s `rgb2rgbcw`
perceptual transform. RGB black is still an explicit ON command with zero
channels; use OFF to turn the light off. Invalid values and unsupported color
modes send no write packets; values are rejected, not clamped.

A setter succeeds only for a matching `method:"setPilot"`, JSON boolean
`result.success:true`, and **no** top-level `error` key. A nil reply is a timeout;
false, numeric/string success values, wrong methods, and malformed JSON are
invalid responses. An ACK is not a state snapshot: `getState` always requests
fresh `getPilot`; discovery and setter values are never cached optimistically.
Missing reported fields remain nil; malformed types/values and empty snapshots
are rejected rather than presented as real state.

UDP is lossy: pywizlight resends at 0, 0.75, 2.25, 5.25 s ... and matches the
reply by `method`. Our unchanged transport uses a fresh request socket, filters
by host, and retries every 0.5 s within a 1.5 s driver timeout. Only idempotent
absolute setters are exposed—no toggles or relative adjustments. Method matching
is not authentication or a transaction identifier; an ACK may not prove the
physical result, so integrations should verify fresh readback. There are no
cloud calls, credentials, port-forwarding, or firewall changes.

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
