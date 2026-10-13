# Feature: smart-home-local

Local-first control of WiZ and CozyLife smart lights from a Mac, as a native Swift
menu bar app with a CLI. This document is the specification; read it until `## Log`.
TDD: strict (Swift Testing via `swift test`). Stack decision: all-Swift (L2).

## Specs

- S1 Project at `~/Development/proyectos/smart-home-local` with Git, "Crea un README.md explicando: objetivo, arquitectura, dispositivos soportados, estado actual del proyecto" and "un .gitignore apropiado".
- S2 Modular architecture: "Cada fabricante debe implementar una interfaz común aproximadament SmartDevice getState() turnOn() turnOff() setBrightness() setColor() setColorTemperature()". "Esto debe permitir agregar posteriormente: LG webOS, tiras LED, enchufes inteligentes, ESP32, Matter, Home Assistant sin reescribir todo el proyecto."
- S3 Discovery command (L2: `swift run shl discover` instead of `npm run discover`) showing:
  ```
  Smart Home Discovery

  [WiZ]
  192.168.1.35
  Model: ...
  State: ON

  [CozyLife]
  192.168.1.42
  Model: ...
  State: OFF
  ```
  "No hardcodees las IP." "No hagas escaneos agresivos de toda la red si el protocolo ofrece broadcast/mDNS/SSDP u otro mecanismo de descubrimiento."
- S4 "No asumas protocolos, puertos, endpoints ni formatos de mensajes. Investiga y verifica cada implementación antes de usarla." Research lives in `docs/protocols.md` with sources.
- S5 (Phase 4, later) CLI control: `> devices`, `> select 1`, `> on`, `> brightness 50`, `> color 255 0 0`, `> status`, `> off`. "Antes de enviar cualquier comando potencialmente incorrecto, verifica el protocolo."
- S6 (Phase 5, later) Native macOS menu bar app ("quisiera que fuera una app nativa de mac. que se abra de arriba"): on/off, brightness slider, color picker, color temperature, connected/disconnected, real device state. "Mantén frontend y protocolo de dispositivos desacoplados." Only after CLI control works.
- S7 Security: local only; no port forwarding, no firewall changes, no secrets in Git; if CozyLife needs a token, use env vars + `.env.example`, `.env` ignored.
- S8 Reverse engineering: if CozyLife lacks documentation, stop and explain "1. qué sabemos 2. qué falta descubrir 3. qué tráfico o aplicación necesitaríamos analizar 4. si REA (https://github.com/morluto/rea) puede ayudarnos 5. qué método de análisis propones". Only the user's own devices on the user's own network.
- S9 Plan fallback: "si la investigacion falla o no encuentra usar rea mcp para hacer ingenieria inversa y cinocer y hacer la app" (see section below).

## Tasks

| ID | Specs | Route | Status | Commit |
|----|-------|-------|--------|--------|
| T1 | S1, S4, S9 | inline | in progress | — |
| T2 | S2 | inline (TDD) | pending | — |
| T3 | S3 | inline (TDD) | pending | — |
| T4 | S3 | inline (real LAN run) | pending | — (no code) |
| T5 | S5 | pending | pending | — |
| T6 | S4, S7, S8 | pending: verify CozyLife TCP 5555 read-only query on the real device | pending | — |
| T7 | S6 | pending: SwiftUI `MenuBarExtra` app target | pending | — |

Route evidence: each task is a single understood unit inside one package; no delegation trigger fired (no 2+ independent writer units).

## Fallback: reverse engineering with REA MCP (S8, S9)

If protocol research fails — public docs and open-source projects (pywizlight,
cozylife/hass_cozylife_local_pull and forks) do not explain how our specific device
behaves, or the device answers in a format we cannot verify — we do NOT invent the
protocol. Instead:

1. Stop and report: what we know, what is missing, which traffic/app we would analyze.
2. Use the REA MCP server (https://github.com/morluto/rea, available in this
   environment as `mcp__rea`) to reverse engineer artifacts we own: the CozyLife
   (or WiZ) Android APK / macOS-iOS app bundle, or firmware dumps of our own device,
   to recover message formats, ports, DP ids and any key derivation.
3. Optionally confirm with passive capture of traffic between the Mac/phone and our
   own device on our own network (e.g. Wireshark on the Mac's interface), never other
   people's devices.
4. Feed the verified findings back into `docs/protocols.md`, then implement the app.

## Log

- L1 (user, verbatim, abridged only where the original message itself was cut): "Quiero iniciar un proyecto nuevo para controlar mis focos inteligentes desde mi Mac de forma local, sin depender de las aplicaciones oficiales siempre que sea posible. Tengo actualmente: - Un foco WiZ - Un foco/dispositivo compatible con CozyLife - Ambos están conectados a la misma red local que mi Mac. [...] Primero: 1. crea la carpeta 2. inicializa el proyecto 3. investiga WiZ y CozyLife 4. crea la arquitectura base 5. implementa descubrimiento WiZ 6. prueba si detectamos mi foco. Después DETENTE. [...] No continúes con la interfaz gráfica hasta comprobar que realmenteal menos un foco. y al final añade dentro del md del plan que si la investigacion falla o no encuentra usar rea mcp para hacer ingenieria inversa y cinocer y hacer la app. quisiera que fuera una app nativa de mac. que se abra de arriba deable, me ayudas?"
- L2 (user decision): Stack = "Todo en Swift (recomendado)": Swift Package with SmartHomeCore + CLI + MenuBarExtra app; commands become `swift run shl ...` instead of npm.
