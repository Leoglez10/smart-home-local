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
- S6 (Phase 5, authorized L12: "empieza a haver la interfaz grafica") Native macOS menu bar app ("quisiera que fuera una app nativa de mac. que se abra de arriba"): on/off, brightness slider, color picker, color temperature, connected/disconnected, real device state. "Mantén frontend y protocolo de dispositivos desacoplados." Only after CLI control works.
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
| T7 | S2, S6, S7 | delegated: parallel disjoint presentation model/tests and SwiftUI app/package/docs | done: 77 tests/9 suites, build and 29 CLI checks exit 0, diff check clean; independent verifier: no blockers, S2/S6/S7 PASS; visual proof pending via `--demo` | — (no commit authorization) |

Route evidence T1–T4: inline. T5 uses two independent units heavier than startup: WiZ driver/codec/tests/protocol notes, and protocol-agnostic CLI session/main/tests/README. Strict TDD via Swift Testing; run RED before behavior, GREEN after. Parent integrates and tests real device; no CozyLife writes or UI. Forecast: ~700–1000 authored lines including tests/docs, two work-unit commits (driver then CLI); no PR publishing in this scope. No size-based code compression.

T7 route evidence: two disjoint worker units launched in parallel (model+tests, and SwiftUI/package/README) as planned. Both subagent workers errored after leaving complete work (client runtime failure; no report): the model worker left the full test suite (RED) and the view worker left complete views, package wiring, and parse-clean files. Parent completed the unit inline: implemented `MenuBarModel` against the worker tests (GREEN), repaired two compile errors (access control on parameterized tests, Quickdraw `RGBColor` name collision), updated README, and ran the seam checks. Independent verifier (unassessable tier) ran in an isolated scratch copy: all five authorized checks exit 0, S2/S6/S7 PASS, no blockers; view-layer regression coverage and visual proof are the declared remaining gaps (L12).

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

- L22 (user): "subelo a mi github, crea un repo y añadele un readme, usa la skill de /readme-completo"; visibility chosen: "Público, quitando datos de mi red". Real LAN IPs, a bulb MAC, and a link-local IP were replaced with RFC 5737 / redacted values in this document and across the whole history with git filter-repo (a local backup bundle stays in the ignored .build/). The commits before the first redacted one kept their hashes. Work committed as feat(cli), fix(transport), and feat(app). README rewritten with readme-completo (audience split, quick start, usage, CLI, data location, troubleshooting, limitations, architecture, security), with anchors, paths, claims, and a secrets scan verified. No LICENSE was added (the user's decision).

- L21 (user): "podemos ponerle que se renombren las luces que encontremos?" Added local device names: `MenuBarModel.rename(_:to:)` / `customName(for:)` keyed by vendor+identifier, trimmed and capped at 40 characters, empty restores the automatic label; names are persisted in RememberedDevices (backward-compatible decoding of data saved before names existed), removed on forget, and never sent to devices. UI: context menu "Rename…" opens inline editing (Enter/Save commits, Esc/Cancel aborts). TDD: 4 new tests, RED (missing members) then GREEN. Checks: build OK, 89 tests/10 suites, 29 CLI checks, diff check clean, 0% CPU at rest; reinstalled to /Applications. The inline editing UI was not exercised automatically.

- L20 (user): "esto puede ser una app instalable en mi lap?" then chose "Sí, en /Applications". Added `scripts/install.sh` (release build, app bundle with Info.plist: bundle ID dev.leoglez.smart-home-local, LSUIElement, NSLocalNetworkUsageDescription, macOS 14; ad-hoc codesign; ditto into /Applications; `--build-only`; exit 64 on bad argument). Checks: `sh -n` OK, bad argument exit 64 with usage, install exit 0, `codesign --verify` satisfied, plist keys read back, no quarantine attribute, `open` launched /Applications/Smart Home.app at 0% CPU. Pending: the user must grant the Local Network permission on first discovery; the icon and launch at login were not done.

- L19 (user): "si detecto una luz, al volver a abrir el modal lo olvida, podemos hacer que lo tenga ahi fijado?" Evidence from the app log: discover found 2 devices, then select, then a later discover found only 1, and the old "replace the list" rule dropped the missing light and its selection. All state was also in memory only, so every relaunch started empty. Changed contract, as the user requested: discovery merges by (vendor, identifier), updating found devices and keeping unseen ones as "missing"; a moved selection keeps its selection but needs a reconnect; failed discovery keeps the selection and connection. New: `DeviceStore`/`UserDefaultsDeviceStore` persists identity only (never state); `reconnectIfNeeded()` runs read-only on panel open; `forget()` is reached from the context menu. Diagnostics use `store: nil`. TDD: 3 old contract tests rewritten plus 6 new, RED (missing types) then GREEN. Checks: build OK, 85 tests/10 suites, 29 CLI checks, diff check clean. The panel reopen behavior was not exercised in the GUI; the user's check is pending.

- L18 (user): "en los colores puedes poner que se abra un selector de colores?" Replaced the ColorPicker+Set pair with a rainbow button that opens an in-app popover hue/saturation wheel; dragging only previews, and release sends one setColor followed by readback. Chosen over NSColorPanel, which opens as a separate window that can hide behind or dismiss the menu bar panel. TDD: `RGBColor(hue:saturation:)` in SmartHomeCore, RED (missing init) then GREEN, 2 tests including wrap/clamp/NaN. Checks: build OK, 79 tests/10 suites, 29 CLI checks, diff check clean, 0% CPU at rest. The popover interaction was not exercised automatically (no GUI automation); the user's look is pending.

- L17 (UI redesign + CPU/GPU bug): User asked "mejora la ui de la app". The redesigned panel has a large power button, a reachability pill, sliders that commit once on release (never while dragging), temperature presets, color swatches and a custom color with Set, plus a friendlier empty state and less explanatory text. The user then reported high GPU use. Measured: the user's main load was an orphaned Playwright chrome-headless-shell GPU process (~340-560% CPU, 4 h, not started by this session; left running pending the user's decision). Our app also hit 100% CPU in a sample: `Slider(step: 1)` over 2200...6500 K made AppKit lay out about 4300 tick marks continuously (NSSliderTickMarks/SliderMarkLabels). The old panel had the same flaw. Fix: no `step:`, round on commit. After the fix: 0.0% CPU at rest, demo state renders. Also disambiguated Quickdraw `RGBColor` via a typealias, and `--window --demo` now renders offline fixtures. Checks: build OK, 77 tests/9 suites, 29 CLI checks, diff check clean. Visual layout checked through window OCR only; the user's look is pending.

- L16 (no devices in menu bar): App log showed discover ran with 0 devices. Public log revealed `sendto 169.254.255.255:38899 failed: errno 65`: a new link-local interface en11 (169.254.x.x) made one broadcast target fail, and runBroadcast aborted the whole discovery (CLI affected too). Fix in BSDUDPTransport: skip failing targets, throw only when every target fails. After the fix there is no error, but there are still 0 replies: routes use en0, the gateway 192.0.2.1 answers ping, while all 4 devices (.4, .19, .17, .18) fail ping and unicast read-only getPilot and have no ARP entries, so they are offline on the LAN (power/Wi-Fi). Checks: build OK, 77 tests, 29 CLI checks. The transport fix has no automated test (the BSD socket path is not unit-testable without refactoring).

- L15 (T7 layout bug): User still saw no lights in the menu bar panel (demo too). Root cause: MenuBarExtra sizes to the content's ideal size and the ScrollView with only `maxHeight` collapsed; measured fittingSize 390x203 with 4 devices discovered. Fix: `.frame(minHeight: 320, idealHeight: 520, maxHeight: 560)`; re-measured 390x629. `swift test` 77/9 pass. `--window` diagnostic now prints FITTING-SIZE after 10 s. Real visual confirmation by the user pending.

- L14 (T7 UI diagnosis): User reported the app discovered nothing. Verified read-only: CLI discovery found 2 WiZ and 2 CozyLife; new headless `--discover-once` diagnostic proved the app's model path finds the same 4 devices; new `--window` diagnostic rendered the real panel with those devices (screen OCR evidence), so model and view both work end to end. The empty result came from the stale/demo instance, not a code defect. App relaunched clean with `os_log` observability in MenuBarModel. Learned: SceneBuilder rejects plain boolean `if` (only `#available`), so the diagnostic window is hosted in an NSWindow from the app delegate. User demanded Orca never be used again (preference saved in memory).

- L13 (T7 checks and independent verifier): Parent seam `swift test && swift build && python3 -I Tests/cli-checks.py .build/debug/shl && git diff --check` all exit 0: 77 tests in 9 suites (20 MenuBarModel tests), 29 public argument checks. `swiftc -frontend -parse Sources/SmartHomeMenuBar/*.swift` exit 0. Native ASSESS unassessable (untracked declaration required) → treated as high: independent `gentle-ai-verify` ran in an isolated fresh scratch copy (same five checks exit 0) and inspected code: S2 decoupling PASS (app imports only SmartHomeCore abstractions; no codec/packet construction; CozyLife never connects), S6 PASS at model layer (readback-after-write, explicit Apply drafts, reachability labels, inert init; view layer structural-only per L12), S7 PASS (manual discovery, no fixed IPs/credentials/persistence, demo transport-free). No candidate-caused blockers. Residual gaps declared: view-layer regressions (onChange/apply wiring), NSColor conversion path, and real visual proof — pending the user's `swift run SmartHomeMenuBar --demo` look; no live device commands were sent and none are authorized.

- L12 (user authorization): "empieza a haver la interfaz grafica". Continue T7 independently of unfinished T5 delivery bookkeeping; preserve all existing staged work. Initial UI uses manual discovery and explicit apply, reads real state after writes, shows unknown/unconfirmed honestly, and exposes no CozyLife control. Verification uses fakes only; no live device commands. T7 route: two independent units with disjoint edit surfaces, model/tests and SwiftUI/package/README, launched together. Forecast roughly 500–700 authored lines including tests and docs; necessary UI, testable state logic and checks stay readable. No publishing or commits authorized. Strict TDD via Swift Testing for model behavior; compile/structural checks for native views, visual proof pending.

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
