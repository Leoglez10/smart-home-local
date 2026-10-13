# smart-home-local

Control smart lights from a Mac **over the local network only**, without vendor
apps or cloud when possible. Target: a native macOS menu bar app plus a CLI.

## Architecture

All-Swift package:

```
Package.swift
Sources/
  SmartHomeCore/          protocol-agnostic core + vendor drivers
    SmartDevice.swift     common interface every vendor implements
    Discovery.swift       DiscoveryProvider + aggregated discovery
    Transport/            UDP/TCP helpers (BSD sockets)
    Vendors/WiZ/          WiZ codec + driver + discovery
    Vendors/CozyLife/     CozyLife codec (+ driver once verified)
  shl/                    CLI (`swift run shl discover`)
  (later) SmartHomeMenuBar/  SwiftUI MenuBarExtra app
Tests/SmartHomeCoreTests/ Swift Testing unit tests (no network)
docs/protocols.md         verified protocol notes with sources
odd/tasks/                feature plan and progress
```

- **SmartDevice** — `getState`, `turnOn`, `turnOff`, `setBrightness`,
  `setColor`, `setColorTemperature`, plus `capabilities` so unsupported
  features are reported instead of guessed.
- **DiscoveryProvider** — one per vendor. New vendors (LG webOS, LED strips,
  plugs, ESP32, Matter, Home Assistant) add a provider + driver without
  touching the rest.
- Codecs (message building/parsing) are pure and unit tested; network I/O is
  isolated in the transport layer. The UI will only depend on `SmartDevice`.

## Supported devices

| Vendor | Discovery | Control | Status |
|---|---|---|---|
| WiZ | UDP broadcast :38899 | UDP JSON (`getPilot`/`setPilot`) | discovery implemented |
| CozyLife | UDP broadcast :6095 | TCP :5555 JSON | protocol researched, unverified on device |

## Usage

```sh
swift test                 # unit tests
swift run shl discover     # find devices on the LAN
```

## Security

Local only: no port forwarding, no firewall changes, no cloud accounts. Secrets,
if ever needed, go in `.env` (git-ignored) with a `.env.example` template.

## Status

Phase 3 (discovery). CLI control, CozyLife verification, and the menu bar app
are next. See `odd/tasks/smart-home-local.md`.
