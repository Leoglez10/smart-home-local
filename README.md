# smart-home-local

Control smart lights from a Mac **over the local network only**, without vendor
apps or cloud when possible. The CLI supports WiZ control; the native macOS menu
bar app comes later. CozyLife remains discover-only.

## Quick start

```sh
swift run shl --help       # usage and session commands; no network activity
swift run shl discover     # read-only discovery of WiZ and CozyLife on the LAN
swift run shl devices      # read-only WiZ discovery/configuration, then a command session
```

`devices` prints a numbered list using model, vendor ID, and freshly discovered
address—not invented room names. Select a device before controlling it:

```text
> select 1
> status
> on
> brightness 50
> color 255 0 0
> temperature 2700
> off
> quit
```

| Session command | Behavior |
|---|---|
| `devices` | List connected drivers without rediscovering or writing |
| `select <number>` | Select from the numbered list; selection does not change power |
| `on`, `off` | Set power explicitly |
| `brightness <0...100>` | Set percent; WiZ treats 0 as OFF, nonzero values turn it ON |
| `color <r> <g> <b>` | Set direct RGB channels, each 0...255; WiZ turns ON |
| `temperature <kelvin>` | Set temperature within that device's verified range; WiZ turns ON |
| `status` | Read actual state from the selected device |
| `help`, `quit` | Show commands or exit cleanly |

Every successful control command reads state back from the device. Missing fields
are `unknown`, never filled from a setter cache. A successful read reports
`Reachability: reachable`; request errors leave reachability unconfirmed and go
to stderr. Invalid input, missing selection, unsupported capabilities, and
out-of-range values are rejected before any control write.

Stdin can be piped, without interactive prompts:

```sh
printf 'devices\nselect 1\nstatus\nquit\n' | swift run shl devices
```

This example performs read-only LAN operations. EOF also ends the session.
Command errors are reported without ending the session. There is no CozyLife
control driver in this entry point.

### Discovery options and argument safety

`swift run shl discover --timeout 5` adjusts the discovery window. The timeout
must be finite, greater than 0, and at most 30 seconds; the default is 4 seconds.
Discovery still displays both vendors, including unknown states where unverified.

All top-level arguments are validated before network activity. Unknown commands,
unknown options, extra tokens, and invalid timeouts produce exit code 64 and
stderr usage. `devices` accepts no options. Help exits 0 without network activity;
discovery exits 1 if a vendor discovery fails.

## Architecture

All-Swift package:

```text
Package.swift
Sources/
  SmartHomeCore/           protocol-agnostic core + vendor drivers
    SmartDevice.swift      common interface every vendor implements
    Discovery.swift        DiscoveryProvider + aggregated discovery
    CLI/DeviceSession.swift command parsing, selection, and real state reporting
    Transport/             UDP/TCP helpers (BSD sockets)
    Vendors/WiZ/           WiZ codec, driver, and discovery
    Vendors/CozyLife/       CozyLife discovery codec/provider only
  shl/                     executable discovery and command-session wiring
  (later) SmartHomeMenuBar/ SwiftUI MenuBarExtra app
Tests/SmartHomeCoreTests/   Swift Testing unit tests (fake transports/devices)
Tests/cli-checks.py         public help/rejected-argument checks (no valid discovery)
docs/protocols.md          verified protocol notes with sources
odd/tasks/                 feature plan and progress
```

- **SmartDevice** exposes state, power, brightness, color, temperature, and
  capabilities. `DeviceSession` depends only on this interface plus verified
  temperature-range metadata; it knows no vendor packet formats.
- **DiscoveryProvider** is one per vendor. New vendors (LG webOS, LED strips,
  plugs, ESP32, Matter, Home Assistant) add a provider and driver without
  rewriting the command session or future UI.
- Codecs are pure and unit tested; network I/O stays in transports. The executable
  connects WiZ drivers using fresh discovery results and passes them to the
  session. The future UI will also depend on `SmartDevice`.

## Supported devices and status

| Vendor | Discovery | Control | Status |
|---|---|---|---|
| WiZ | UDP broadcast :38899 | UDP JSON (`getPilot`/`setPilot`) | CLI driver implemented; capabilities and temperature range queried per device |
| CozyLife | UDP broadcast :6095 | Not exposed | Discover-only; TCP state/control verification pending |

Phase 4: WiZ CLI control implemented, with fake-device and executable argument
checks. Real-device CLI acceptance is a separate supervised check. CozyLife
verification and the native menu bar UI remain future work; see
`odd/tasks/smart-home-local.md` and `docs/protocols.md`.

## Development checks

```sh
swift test --filter DeviceSessionTests
swift test
python3 -I Tests/cli-checks.py .build/debug/shl
```

Swift tests use fake devices/transports, not live hardware. Python checks only
help and rejected top-level arguments; they assert exit status, stdout, and
stderr. Actual LAN discovery and control must be tested separately on authorized
devices.

## Security

Local only: no subnet sweeps, port forwarding, firewall changes, or cloud
accounts. No fixed device IPs or private captures are required. Secrets, if ever
needed by a future verified driver, go in `.env` (git-ignored) with a
`.env.example` template; never commit credentials. CozyLife control and the UI
are intentionally out of scope for this phase.
