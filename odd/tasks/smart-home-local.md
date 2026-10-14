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
- S5 (Phase 4, authorized L6) CLI control: `> devices`, `> select 1`, `> on`, `> brightness 50`, `> color 255 0 0`, `> status`, `> off`. "Antes de enviar cualquier comando potencialmente incorrecto, verifica el protocolo."
- S6 (Phase 5, later) Native macOS menu bar app ("quisiera que fuera una app nativa de mac. que se abra de arriba"): on/off, brightness slider, color picker, color temperature, connected/disconnected, real device state. "Mantén frontend y protocolo de dispositivos desacoplados." Only after CLI control works.
- S7 Security: local only; no port forwarding, no firewall changes, no secrets in Git; if CozyLife needs a token, use env vars + `.env.example`, `.env` ignored.
- S8 Reverse engineering: if CozyLife lacks documentation, stop and explain "1. qué sabemos 2. qué falta descubrir 3. qué tráfico o aplicación necesitaríamos analizar 4. si REA (https://github.com/morluto/rea) puede ayudarnos 5. qué método de análisis propones". Only the user's own devices on the user's own network.
- S9 Plan fallback: "si la investigacion falla o no encuentra usar rea mcp para hacer ingenieria inversa y cinocer y hacer la app" (see section below).

## Tasks

| ID | Specs | Route | Status | Commit |
|----|-------|-------|--------|--------|
| T1 | S1, S4, S9 | inline | done | 7f41d32 |
| T2 | S2 | inline (TDD) | done | 159823a |
| T3 | S3 | inline (TDD) | done | 9c138c2 |
| T4 | S3 | inline (real LAN run) | done: WiZ model/state verified; CozyLife discovery verified, state pending T6 | — (evidence only) |
| T5 | S2, S4, S5, S7 | delegated: two parallel, disjoint units (WiZ driver + generic CLI) | in progress: user accepted 1 K restoration discrepancy; final assessment/commits pending | — |
| T6 | S4, S7, S8 | pending: verify CozyLife TCP 5555 read-only query on the real device | pending | — |
| T7 | S6 | pending: SwiftUI `MenuBarExtra` app target | pending | — |

Route evidence T1–T4: inline. T5 uses two independent units heavier than startup: WiZ driver/codec/tests/protocol notes, and protocol-agnostic CLI session/main/tests/README. Strict TDD via Swift Testing; run RED before behavior, GREEN after. Parent integrates and tests real device; no CozyLife writes or UI. Forecast: ~700–1000 authored lines including tests/docs, two work-unit commits (driver then CLI); no PR publishing in this scope. No size-based code compression.

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

- L11 (user): "si" in response to "¿aceptas cerrar la prueba con esa diferencia documentada de 1 K, sin enviar más comandos al foco?". Exact-restoration assertion remains FAILED (not converted to PASS); user accepts documented discrepancy as sufficient closure proof. No further physical writes authorized for this closure.
- L10 (independent verifier): No confirmed candidate-caused blocker; isolated Swift tests 57/8 suites passed, Python 29 argument checks exit0, diff check exit0. S2/S3/S7 PASS; S4 research source revalidation not independent (parent owns it), S5 controls deterministic/live pass but exact restoration partial and executable EOF coverage not run. Same-method stale UDP correlation is a documented limitation; no code bug inferred for 1 K discrepancy. Human decision requested: accept documented restoration difference without more lamp writes before closing T5. Native first ASSESS was unassessable because untracked candidate files require explicit declaration, so independent high-risk verification was run; final candidate assessment/review routing remains pending after scope/proof closure.
- L8 (T5 checks): Parent seam `swift test && python3 -I Tests/cli-checks.py .build/debug/shl && git diff --check` exit 0: 57 tests in 8 suites, 29 public argument checks. Driver RED observed against empty implementation; CLI parent behavioral RED exit 1 (14 tests, 78 expected failures), both writers report GREEN. Independent verifier running.
- L9 (T5 real-device check): Three public piped `shl devices` processes, each exit 0 and empty stderr. Actual initial snapshot ON, 82%, 3685 K (different from earlier research snapshot). Verified on, brightness 50, color 255 0 0, temperature 2700, off/status and quit with real getPilot readbacks. Finally restored temperature/brightness/power: immediately 3685 K, then final ON/82%/3686 K. Whole acceptance command exited 1 because exact restoration expected 3685 K; no cause inferred, no automatic repeat writes. All requested controls passed; exact-restoration proof remains partial (1 K difference).
- L6 (authorization): parent asked "¿Ese «ok» autoriza continuar con la CLI de WiZ y probar encendido/apagado, brillo, color y temperatura en tu foco real, todavía sin crear la interfaz?"; user answered "si, continua".
- L7 (read-only real-device evidence): WiZ discovered automatically at .19, MAC redacted. getSystemConfig: ESP01_SHRGB1C_31, fwVersion 1.35.0. getModelConfig: cctRange [2200,2699,6500,6500], nowc 1; pywizlight infers RGB from module name, min/max cctRange => 2200–6500 K. getUserConfig minDimming 0. Initial getPilot: state true, temp 3714 K, dimming 83, sceneId 0. Real tests will restore this state and verify readback, not merely trust setPilot success.

- L1 (user, verbatim, abridged only where the original message itself was cut): "Quiero iniciar un proyecto nuevo para controlar mis focos inteligentes desde mi Mac de forma local, sin depender de las aplicaciones oficiales siempre que sea posible. Tengo actualmente: - Un foco WiZ - Un foco/dispositivo compatible con CozyLife - Ambos están conectados a la misma red local que mi Mac. [...] Primero: 1. crea la carpeta 2. inicializa el proyecto 3. investiga WiZ y CozyLife 4. crea la arquitectura base 5. implementa descubrimiento WiZ 6. prueba si detectamos mi foco. Después DETENTE. [...] No continúes con la interfaz gráfica hasta comprobar que realmenteal menos un foco. y al final añade dentro del md del plan que si la investigacion falla o no encuentra usar rea mcp para hacer ingenieria inversa y cinocer y hacer la app. quisiera que fuera una app nativa de mac. que se abra de arriba deable, me ayudas?"
- L2 (user decision): Stack = "Todo en Swift (recomendado)": Swift Package with SmartHomeCore + CLI + MenuBarExtra app; commands become `swift run shl ...` instead of npm.
- L4 (user): "ya prendi el de wiz, no se su ip"
- L5 (evidence, T4): `.build/debug/shl discover --timeout 5` exited 0 after the user powered on WiZ. Found WiZ at 192.0.2.19, module ESP01_SHRGB1C_31, State ON (getSystemConfig/getPilot). Also found CozyLife at 192.0.2.17 and .18, pid qwialM, state unknown (no TCP query yet). No control commands sent. Stop here per S3/L1; CLI control and native UI remain future work.
- L3 (evidence, T4): `swift run shl discover --timeout 5` on 192.0.2.11/24 found 2 CozyLife devices (192.0.2.17 and 192.0.2.18, pid `qwialM`) answering UDP 6095. No WiZ reply to the pywizlight registration probe on UDP 38899, neither from an ephemeral port nor bound to 38899, to 255.255.255.255 and 192.0.2.255. Broadcast works on this LAN (CozyLife answered), so the WiZ is likely powered off at the switch, on another network/SSID, or isolated. Next: user confirms the WiZ IP (WiZ app → device settings, or router DHCP list) to try a unicast `getPilot`.
