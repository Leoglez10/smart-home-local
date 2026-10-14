<div align="center">

# Smart Home (smart-home-local)

### Control your smart lights from your Mac over your local network — no vendor app, no cloud.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![UI](https://img.shields.io/badge/UI-SwiftUI%20MenuBarExtra-blue)
![Network](https://img.shields.io/badge/network-LAN%20only-green)

</div>

> This README is for both people who just want to use the app and developers.
> To install and use it, read [Install the app](#install-the-app) and [Using the app](#using-the-app).
> To work on the code, go to [Development](#development).

> 🚀 **In a hurry?**
>
> 1. `git clone https://github.com/Leoglez10/smart-home-local.git && cd smart-home-local`
> 2. `scripts/install.sh`
> 3. Open **Smart Home** from Spotlight; a light bulb appears in the menu bar.
> 4. Press **Discover** and allow **Local Network** access when macOS asks.

## Contents

- [What is it?](#what-is-it)
- [Features](#features)
- [Supported devices](#supported-devices)
- [Install the app](#install-the-app)
- [Using the app](#using-the-app)
- [Command line (shl)](#command-line-shl)
- [Where data lives](#where-data-lives)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)
- [Development](#development)
- [Architecture](#architecture)
- [Security and privacy](#security-and-privacy)
- [Related documentation](#related-documentation)
- [License](#license)

## What is it?

Smart Home is a small macOS menu bar app plus a command-line tool that finds the
smart lights on your Wi‑Fi and lets you turn them on and off, dim them, and change
their color or color temperature. It talks to the lights directly over your local
network using their own local protocols, so it works without the manufacturer's
app or account.

Think of it as a light switch panel that lives in your Mac's menu bar.

Who it is for:

| Person | What they get |
|---|---|
| Someone with WiZ lights and a Mac | A menu bar panel to control them without the WiZ app |
| A developer | A Swift package with a vendor-independent `SmartDevice` interface to add new devices |

## Features

- ✅ Finds WiZ and CozyLife devices with each vendor's broadcast discovery (no network scanning).
- ✅ Power, brightness, color temperature (with Warm / Neutral / Daylight presets) and RGB color for WiZ.
- ✅ Color swatches plus a color wheel; one command is sent only when you release the control.
- ✅ Shows the state the light actually reports after every change — never a guess.
- ✅ Connection indicator: Unconfirmed, Reachable, or Unavailable.
- ✅ Remembers found lights, the selected light, and your own names for them across restarts.
- ✅ Rename or forget a light from its right-click menu.
- ✅ Installs as a normal Mac app that lives only in the menu bar (no Dock icon).
- ✅ `shl` command-line tool for discovery and an interactive control session.
- 🧪 CozyLife is **discover-only**: it is listed, but it cannot be controlled yet.

No screenshots yet _(pending)_.

## Supported devices

| Vendor | Discovery | Control | Status |
|---|---|---|---|
| WiZ | UDP broadcast, port 38899 | UDP JSON (`getPilot` / `setPilot`) | Working; capabilities and temperature range are read from each light |
| CozyLife | UDP broadcast, port 6095 | — | Discover-only; control (TCP 5555) is not verified, so it is disabled |

Tested with a WiZ RGB bulb (`ESP01_SHRGB1C_31`, firmware 1.35.0). Other WiZ models
are expected to work through the same protocol, but have not been tested.

## Install the app

### Requirements

- macOS 14 (Sonoma) or later.
- Xcode or the Swift 6 toolchain (the app is built from source on your Mac).
- Your lights on the same Wi‑Fi network as the Mac.

### Install

```sh
git clone https://github.com/Leoglez10/smart-home-local.git
cd smart-home-local
scripts/install.sh
```

The script builds a release version, packages it as `Smart Home.app`, signs it
for this Mac only (an "ad-hoc" signature; no Apple Developer account needed), and
copies it to `/Applications`, replacing any older copy. To only build the app
inside the project, use `scripts/install.sh --build-only` (output:
`.build/Smart Home.app`).

### First launch

1. Open **Smart Home** from Spotlight, Launchpad, or `/Applications`.
2. Click the light bulb icon in the menu bar.
3. Press **Discover**.
4. macOS asks for **Local Network** permission. Allow it — without it the app
   cannot see any light.

### Update

Pull the latest code and run `scripts/install.sh` again. Your remembered lights
and names are kept.

## Using the app

### Find and pick a light

1. Press **Discover** (or the circular arrow in the header).
2. Click a light in the list. The app connects and reads its real state; this
   only reads, it does not change the light.

> 💡 A new search never removes lights from the list. A light that did not answer
> stays listed with **"Not found in last search"**, because Wi‑Fi lights sometimes
> miss a single search.

### Control a light

| Control | What it does |
|---|---|
| Power button | Turns the light on or off |
| Brightness slider | Sets brightness when you **release** the slider (0 % turns WiZ off) |
| Temperature slider and presets | Sets white light from warm to daylight, within the light's own range |
| Color swatches | Sets that color with one click |
| Rainbow button | Opens a color wheel; tap or drag, and the color is sent when you release |
| Refresh button | Reads the current state again |

Dragging a slider or across the color wheel sends nothing. After every command the
app reads the light back and shows that result. `Unknown` means the light did not
report that value.

### Rename or forget a light

Right-click a light:

- **Rename…** — type a name and press Enter (Esc cancels). Names stay on this Mac,
  are never sent to the light, and are kept when the light changes IP address. Up
  to 40 characters; leave it empty to go back to the automatic name.
- **Forget This Device** — removes it from the list together with its name.

## Command line (shl)

```sh
swift run shl --help        # usage; no network activity
swift run shl discover      # find WiZ and CozyLife lights (read-only)
swift run shl devices       # find WiZ lights, then open a control session
```

`discover --timeout <seconds>` changes the search window (more than 0, at most
30; default 4). Inside `devices`:

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
| `devices` | List connected lights without searching again |
| `select <number>` | Choose a light; does not change it |
| `on`, `off` | Set power |
| `brightness <0...100>` | Set brightness; 0 turns WiZ off |
| `color <r> <g> <b>` | Set RGB, each 0...255 |
| `temperature <kelvin>` | Set color temperature within the light's range |
| `status` | Read the actual state |
| `help`, `quit` | Show commands or exit |

Commands can be piped: `printf 'devices\nselect 1\nstatus\nquit\n' | swift run shl devices`.
Invalid arguments exit with code 64; `discover` exits 1 if a vendor's search fails.

## Where data lives

The app stores only the identity of each light (vendor, address, identifier,
model), the selected light, and your names, as JSON in macOS user defaults under
the key `rememberedDevices`. Light state is never stored, because it would be
stale.

| Run as | Defaults domain |
|---|---|
| Installed `Smart Home.app` | `dev.leoglez.smart-home-local` |
| `swift run SmartHomeMenuBar` | the executable's own domain, separate from the installed app |

To forget everything for the installed app:

```sh
defaults delete dev.leoglez.smart-home-local rememberedDevices
```

Nothing else is saved, and there is nothing to back up beyond your light names.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Discover finds nothing | Local Network permission denied | System Settings → Privacy & Security → Local Network → enable **Smart Home** |
| Discover finds nothing, permission is on | Lights are off at the wall switch or not on this Wi‑Fi | Turn them on, wait about 20 seconds, and search again; check `swift run shl discover` |
| A light shows "Not found in last search" | It missed that search or is offline | Search again; if it never comes back, right-click → Forget |
| Light shows Unavailable | It stopped answering | Check power and Wi‑Fi, then press Refresh |
| CozyLife cannot be controlled | Control is not implemented yet | Expected; see [Limitations](#limitations) |
| Panel looks empty | App started from an old build | Run `scripts/install.sh` again and reopen the app |

For development checks without the menu bar, the app has diagnostic flags:
`--discover-once` prints one real search and exits; `--window` shows the panel in
a normal window; `--demo` uses fake in-memory lights and never touches the network.

## Limitations

- CozyLife devices are discover-only.
- Only tested with one WiZ RGB bulb model.
- Built from source; there is no prebuilt download or automatic updates.
- No app icon and no "open at login" option yet.
- No automated tests for the SwiftUI views; only the app model and the core are tested.
- macOS only.

## Development

### Requirements

Swift 6 toolchain (Xcode) on macOS 14 or later. No third-party dependencies.

### Commands

```sh
swift build                                   # build everything
swift test                                    # unit tests (fake devices, no network)
python3 -I Tests/cli-checks.py .build/debug/shl   # CLI help/argument checks (no network)
swift run SmartHomeMenuBar --demo             # run the menu bar app with fake lights
scripts/install.sh --build-only               # package Smart Home.app
```

Tests use fake transports and devices; they never send anything to real lights.
Testing on real hardware is a separate, manual step on your own devices.

### Project structure

```text
Package.swift
Sources/
  SmartHomeCore/              core library, independent of any UI
    SmartDevice.swift         common interface every vendor implements
    Discovery.swift           DiscoveryProvider + aggregated discovery
    CLI/DeviceSession.swift   shl command session
    UI/                       MenuBarModel, DeviceStore, color helpers
    Transport/                UDP (BSD sockets)
    Vendors/WiZ/              WiZ codec, driver, discovery
    Vendors/CozyLife/         CozyLife discovery only
  shl/                        command-line executable
  SmartHomeMenuBar/           SwiftUI menu bar app
Tests/SmartHomeCoreTests/     Swift Testing unit tests
Tests/cli-checks.py           CLI argument checks
scripts/install.sh            build, sign, and install Smart Home.app
docs/protocols.md             verified protocol notes with sources
odd/tasks/                    feature plan and progress log
```

## Architecture

- **`SmartDevice`** is the one interface the CLI and the app use: state, power,
  brightness, color, temperature, and capabilities. Neither knows any vendor's
  packet format.
- **`DiscoveryProvider`** — one per vendor, using that vendor's own broadcast
  discovery. New device types (for example LG webOS, LED strips, plugs, ESP32,
  Matter, Home Assistant) add a provider and a driver without rewriting the CLI or
  the app.
- **Codecs** build and parse messages and are pure and unit tested; network I/O
  stays in `Transport/`.
- **`MenuBarModel`** runs one operation at a time, sends commands only on explicit
  user actions, and reads the device back after every change.

To add a vendor: implement `DiscoveryProvider` and `SmartDevice` under
`Sources/SmartHomeCore/Vendors/<Vendor>/`, add a `Vendor` case, register the
provider in `DiscoveryService.default()`, and document the verified protocol in
`docs/protocols.md`.

## Security and privacy

- Traffic stays on your local network: UDP broadcast for discovery and UDP
  messages to each light. The code has no internet connections, accounts, or
  telemetry.
- No subnet scanning, port forwarding, or firewall changes.
- No credentials are needed. If a future driver needs a secret, it belongs in a
  git-ignored `.env` with a `.env.example` template.
- Any program on your network can talk to these lights the same way; the lights'
  local protocols have no authentication.

## Related documentation

| Document | Purpose |
|---|---|
| [`docs/protocols.md`](docs/protocols.md) | WiZ and CozyLife local protocols, with sources and what is verified |
| [`odd/tasks/smart-home-local.md`](odd/tasks/smart-home-local.md) | Feature specification, task status, and evidence log |

## License

This repository does not include a license yet, so default copyright applies. Add
a `LICENSE` file before accepting outside contributions.

<div align="center">

Built by [Leoglez10](https://github.com/Leoglez10)

</div>
