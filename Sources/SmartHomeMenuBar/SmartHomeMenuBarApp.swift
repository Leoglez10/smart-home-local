import AppKit
import Observation
import SmartHomeCore
import SwiftUI

@main
@MainActor
struct SmartHomeMenuBarApp: App {
    @NSApplicationDelegateAdaptor(MenuBarAppDelegate.self) private var appDelegate
    @State private var model: MenuBarModel
    private let isDemo: Bool

    init() {
        let arguments = CommandLine.arguments
        let demo = arguments.contains("--demo")
        isDemo = demo
        // Construction is inert. Discovery and reads start only from explicit actions.
        _model = State(initialValue: demo ? OfflineDemo.makeModel() : MenuBarModel())
        if arguments.contains("--discover-once") {
            // Headless diagnostic: run one real discovery, print results, exit.
            Task { await Self.runDiscoverOnce() }
        }
    }

    @MainActor
    private static func runDiscoverOnce() async {
        let model = MenuBarModel(store: nil)
        await model.discover()
        print("DISCOVER-ONCE devices=\(model.devices.count)")
        for device in model.devices {
            print("  [\(device.vendor.displayName)] \(device.address) \(device.model ?? "unknown")")
        }
        if let error = model.errorMessage { print("  errors: \(error)") }
        exit(0)
    }

    var body: some Scene {
        MenuBarExtra("Smart Home", systemImage: "lightbulb") {
            MenuBarPanel(model: model, isDemo: isDemo)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Diagnostic-only host: real wiring, one automatic discovery on appear, normal window.
@MainActor
private struct WindowDiagnosticPanel: View {
    private let isDemo = CommandLine.arguments.contains("--demo")
    @State private var model = CommandLine.arguments.contains("--demo") ? OfflineDemo.makeModel() : MenuBarModel(store: nil)

    var body: some View {
        MenuBarPanel(model: model, isDemo: isDemo)
            .onAppear {
                NSApp.activate(ignoringOtherApps: true)
                Task {
                    await model.discover()
                    // Demo only: select the first light so the control card renders.
                    if isDemo, let first = model.devices.first { await model.select(first) }
                }
            }
    }
}

@MainActor
private final class MenuBarAppDelegate: NSObject, NSApplicationDelegate {
    private var diagnosticWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--window") {
            // Diagnostic mode: show the panel in a normal, inspectable window.
            let hosting = NSHostingView(rootView: WindowDiagnosticPanel())
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 640),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.contentView = hosting
            window.center()
            window.makeKeyAndOrderFront(nil)
            diagnosticWindow = window
            // Report the content's own size, which is what MenuBarExtra uses.
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                print("FITTING-SIZE \(hosting.fittingSize)")
                fflush(stdout)
            }
        }
    }
}

/// Offline fixtures have no transports, sockets, or vendor-driver connection path.
@MainActor
private enum OfflineDemo {
    static func makeModel() -> MenuBarModel {
        let light = DemoLight()
        return MenuBarModel(
            discovery: DiscoveryService(providers: [DemoDiscovery(vendor: .wiz), DemoDiscovery(vendor: .cozyLife)]),
            connector: { _ in
                MenuBarConnection(device: light, temperatureRange: 2200...6500)
            }
        )
    }
}

private struct DemoDiscovery: DiscoveryProvider {
    let vendor: Vendor

    func discover(timeout: TimeInterval) async throws -> [DiscoveredDevice] {
        [DiscoveredDevice(
            vendor: vendor,
            address: "Offline demo",
            identifier: vendor == .wiz ? "demo-wiz" : "demo-cozylife",
            model: vendor == .wiz ? "Demo RGB light" : "Demo discover-only device",
            state: nil
        )]
    }
}

/// Controls change only this actor's memory; getState returns that memory snapshot.
private actor DemoLight: SmartDevice {
    nonisolated let id = "demo-wiz"
    nonisolated let vendor: Vendor = .wiz
    nonisolated let address = "Offline demo"
    nonisolated let name = "Demo RGB light"
    nonisolated let capabilities: DeviceCapabilities = [.power, .brightness, .color, .colorTemperature]
    private var snapshot = DeviceState(isOn: true, brightness: 65, colorTemperature: 3000)

    func getState() async throws -> DeviceState { snapshot }

    func turnOn() async throws { snapshot.isOn = true }

    func turnOff() async throws { snapshot.isOn = false }

    func setBrightness(_ percent: Int) async throws {
        snapshot.brightness = percent
        snapshot.isOn = percent > 0
    }

    func setColor(_ color: SmartHomeCore.RGBColor) async throws {
        snapshot.color = color
        snapshot.colorTemperature = nil
        snapshot.isOn = true
    }

    func setColorTemperature(_ kelvin: Int) async throws {
        snapshot.colorTemperature = kelvin
        snapshot.color = nil
        snapshot.isOn = true
    }
}
