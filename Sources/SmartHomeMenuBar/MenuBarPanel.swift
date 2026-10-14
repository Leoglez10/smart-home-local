import AppKit
import Observation
import SmartHomeCore
import SwiftUI

// AppKit also exports Quickdraw's RGBColor; disambiguate once.
private typealias LightColor = SmartHomeCore.RGBColor

/// Menu bar panel. Every control sends at most one command per user action
/// (tap, or slider release) and the panel only ever shows state read back from the device.
@MainActor
struct MenuBarPanel: View {
    @Bindable var model: MenuBarModel
    let isDemo: Bool
    @State private var editingKey: String?
    @State private var nameDraft = ""
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let error = model.errorMessage { ErrorBanner(message: error) }
                    if model.devices.isEmpty {
                        emptyState
                    } else {
                        deviceList
                    }
                    if let selected = model.selected {
                        if selected.vendor == .wiz {
                            LightCard(model: model, device: selected)
                                .id("\(selected.vendor.rawValue):\(selected.identifier):\(selected.address)")
                        } else {
                            Label("CozyLife devices are discover-only for now.", systemImage: "info.circle")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        }
                    }
                }
                .padding(14)
            }
            // MenuBarExtra sizes to the ideal height; a bare ScrollView collapses.
            .frame(minHeight: 320, idealHeight: 520, maxHeight: 560)
            Divider()
            footer
        }
        .frame(width: 360)
        // Read-only: reconnect a remembered selection when the panel opens.
        .onAppear { Task { await model.reconnectIfNeeded() } }
    }

    // MARK: Header and footer

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.2.fill")
                .font(.title2)
                .foregroundStyle(.yellow.gradient)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Smart Home").font(.headline)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isBusy {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await model.discover() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(model.isBusy)
            .help("Search the local network for lights")
            .accessibilityLabel("Discover devices")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var summary: String {
        if isDemo { return "Offline demo · no network" }
        let wiz = model.devices.filter { $0.vendor == .wiz }.count
        let others = model.devices.count - wiz
        if model.devices.isEmpty { return "Local network only" }
        var parts = ["\(wiz) controllable"]
        if others > 0 { parts.append("\(others) discover-only") }
        return parts.joined(separator: " · ")
    }

    private var footer: some View {
        HStack {
            Label("Local only", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Devices

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.router")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(model.isBusy ? "Searching your network…" : "No lights found yet")
                .font(.headline)
            Text("Make sure your lights are powered on and on the same Wi-Fi as this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await model.discover() }
            } label: {
                Label("Discover", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var deviceList: some View {
        VStack(spacing: 4) {
            ForEach(model.devices.indices, id: \.self) { index in
                let device = model.devices[index]
                if editingKey == RememberedDevices.key(for: device) {
                    renameField(for: device)
                } else {
                    DeviceRow(device: device, customName: model.customName(for: device),
                              isSelected: isSelected(device),
                              isMissing: model.wasMissingInLastDiscovery(device)) {
                        Task { await model.select(device) }
                    }
                    .disabled(model.isBusy)
                    .contextMenu {
                        Button("Rename…") { startRenaming(device) }
                        Button("Forget This Device", role: .destructive) {
                            Task { await model.forget(device) }
                        }
                    }
                }
            }
        }
    }

    // MARK: Renaming (local only; nothing is sent to the device)

    private func renameField(for device: DiscoveredDevice) -> some View {
        HStack(spacing: 6) {
            TextField("Name", text: $nameDraft, prompt: Text("Leave empty for automatic name"))
                .textFieldStyle(.roundedBorder)
                .focused($isNameFieldFocused)
                .onSubmit { finishRenaming(device) }
                .onExitCommand { editingKey = nil }
            Button("Save") { finishRenaming(device) }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            Button("Cancel") { editingKey = nil }
                .controlSize(.small)
        }
        .padding(6)
        .onAppear { isNameFieldFocused = true }
    }

    private func startRenaming(_ device: DiscoveredDevice) {
        nameDraft = model.customName(for: device) ?? ""
        editingKey = RememberedDevices.key(for: device)
    }

    private func finishRenaming(_ device: DiscoveredDevice) {
        model.rename(device, to: nameDraft)
        editingKey = nil
    }

    private func isSelected(_ device: DiscoveredDevice) -> Bool {
        guard let selected = model.selected else { return false }
        return selected.vendor == device.vendor && selected.identifier == device.identifier
            && selected.address == device.address
    }
}

// MARK: - Rows and banners

private struct DeviceRow: View {
    let device: DiscoveredDevice
    let customName: String?
    let isSelected: Bool
    let isMissing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                        .frame(width: 30, height: 30)
                    Image(systemName: device.vendor == .wiz ? "lightbulb.fill" : "powerplug.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? .white : .secondary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.weight(.medium))
                    Text(isMissing ? "Not found in last search · \(device.address)"
                                   : "\(device.vendor.displayName) · \(device.address)")
                        .font(.caption)
                        .foregroundStyle(isMissing ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
                Spacer(minLength: 0)
                if device.vendor == .cozyLife {
                    Text("View only")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                } else if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
            .padding(8)
            .contentShape(Rectangle())
            .background(isSelected ? Color.accentColor.opacity(0.1) : .clear,
                        in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .help("\(device.identifier) · Right-click to rename or forget")
    }

    private var title: String {
        if let customName { return customName }
        guard let model = device.model else { return "\(device.vendor.displayName) device" }
        // Module names like ESP01_SHRGB1C_31 are not friendly; give a readable label.
        if device.vendor == .wiz { return model.contains("RGB") ? "WiZ color light" : "WiZ light" }
        return model
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Light card

@MainActor
private struct LightCard: View {
    @Bindable var model: MenuBarModel
    let device: DiscoveredDevice
    @State private var showsColorWheel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            powerRow
            if model.capabilities.contains(.brightness) {
                CommitSlider(title: "Brightness", systemImage: "sun.max.fill", range: 0...100,
                             observed: model.state?.brightness, unit: "%",
                             isEnabled: canUse(.brightness)) { value in
                    Task { await model.setBrightness(value) }
                }
            }
            if model.capabilities.contains(.colorTemperature), let range = model.temperatureRange,
               range.lowerBound < range.upperBound {
                temperatureSection(range)
            }
            if model.capabilities.contains(.color) {
                colorSection
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
    }

    // Power

    private var powerRow: some View {
        HStack(spacing: 12) {
            Button {
                Task { await model.setPower(!(model.state?.isOn ?? false)) }
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isOn == true ? .white : .primary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(isOn == true ? AnyShapeStyle(lightTint.gradient)
                                                           : AnyShapeStyle(.quaternary)))
            }
            .buttonStyle(.plain)
            .disabled(!canUse(.power))
            .accessibilityLabel(isOn == true ? "Turn off" : "Turn on")
            VStack(alignment: .leading, spacing: 3) {
                Text(powerLabel).font(.title3.weight(.semibold))
                ReachabilityPill(reachability: model.reachability)
            }
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderless)
            .disabled(model.isBusy)
            .help("Read the current state from the light")
            .accessibilityLabel("Refresh state")
        }
    }

    private var isOn: Bool? { model.state?.isOn }

    private var powerLabel: String {
        switch isOn {
        case true?: "On"
        case false?: "Off"
        case nil: "Unknown"
        }
    }

    /// Tint from the observed color or temperature, never from a draft.
    private var lightTint: Color {
        if let rgb = model.state?.color { return Color(rgb) }
        if let kelvin = model.state?.colorTemperature { return Color(kelvin: kelvin) }
        return .yellow
    }

    // Temperature

    private func temperatureSection(_ range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CommitSlider(title: "Temperature", systemImage: "thermometer.medium", range: range,
                         observed: model.state?.colorTemperature, unit: " K",
                         isEnabled: canUse(.colorTemperature)) { value in
                Task { await model.setTemperature(value) }
            }
            Capsule()
                .fill(LinearGradient(colors: [Color(kelvin: range.lowerBound), Color(kelvin: range.upperBound)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 4)
                .accessibilityHidden(true)
            HStack(spacing: 6) {
                ForEach(temperaturePresets(range), id: \.kelvin) { preset in
                    Button(preset.name) { Task { await model.setTemperature(preset.kelvin) } }
                        .controlSize(.small)
                }
            }
            .disabled(!canUse(.colorTemperature))
        }
    }

    private func temperaturePresets(_ range: ClosedRange<Int>) -> [(name: String, kelvin: Int)] {
        [("Warm", 2700), ("Neutral", 4000), ("Daylight", 6500)]
            .map { ($0.0, min(max($0.1, range.lowerBound), range.upperBound)) }
            .reduce(into: []) { result, preset in
                if !result.contains(where: { $0.kelvin == preset.1 }) { result.append((preset.0, preset.1)) }
            }
    }

    // Color

    private static let swatches: [LightColor] = [
        LightColor(red: 255, green: 60, blue: 40), LightColor(red: 255, green: 150, blue: 0),
        LightColor(red: 255, green: 220, blue: 0), LightColor(red: 40, green: 200, blue: 80),
        LightColor(red: 0, green: 170, blue: 255), LightColor(red: 60, green: 70, blue: 255),
        LightColor(red: 170, green: 60, blue: 255), LightColor(red: 255, green: 60, blue: 170),
    ]

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Color", systemImage: "paintpalette.fill")
                .font(.callout.weight(.medium))
            HStack(spacing: 7) {
                ForEach(Self.swatches, id: \.self) { swatch in
                    Button {
                        Task { await model.setColor(swatch) }
                    } label: {
                        Circle()
                            .fill(Color(swatch))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(.white.opacity(model.state?.color == swatch ? 0.9 : 0),
                                                           lineWidth: 2))
                            .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Set color \(swatch.red), \(swatch.green), \(swatch.blue)")
                }
                Spacer(minLength: 0)
                Button {
                    showsColorWheel.toggle()
                } label: {
                    Circle()
                        .fill(AngularGradient(colors: ColorWheel.hueStops, center: .center))
                        .frame(width: 22, height: 22)
                        .overlay(Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white).shadow(radius: 1))
                }
                .buttonStyle(.plain)
                .help("Choose any color")
                .accessibilityLabel("Open color picker")
                .popover(isPresented: $showsColorWheel, arrowEdge: .bottom) {
                    ColorWheel(observed: model.state?.color, isEnabled: canUse(.color)) { color in
                        Task { await model.setColor(color) }
                    }
                }
            }
            .disabled(!canUse(.color))
        }
    }

    private func canUse(_ capability: DeviceCapabilities) -> Bool {
        !model.isBusy && device.vendor == .wiz && model.capabilities.contains(capability)
    }
}

/// Hue/saturation wheel shown in a popover. Dragging only moves the preview;
/// releasing sends exactly one color command.
private struct ColorWheel: View {
    static let hueStops: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 12).map {
        Color(hue: $0, saturation: 1, brightness: 1)
    }

    let observed: LightColor?
    let isEnabled: Bool
    let commit: (LightColor) -> Void
    @State private var marker: CGPoint?
    @State private var draft: LightColor?
    private let diameter: CGFloat = 200

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(AngularGradient(colors: Self.hueStops, center: .center))
                Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center,
                                             startRadius: 0, endRadius: diameter / 2))
                if let marker {
                    Circle()
                        .strokeBorder(.white, lineWidth: 3)
                        .background(Circle().fill(draft.map { Color($0) } ?? .clear))
                        .frame(width: 22, height: 22)
                        .shadow(radius: 2)
                        .position(marker)
                }
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { pick($0.location) }
                .onEnded { value in
                    pick(value.location)
                    if let draft { commit(draft) }
                })
            .opacity(isEnabled ? 1 : 0.5)
            .allowsHitTesting(isEnabled)
            .accessibilityLabel("Color wheel")
            HStack(spacing: 8) {
                Circle().fill(observed.map { Color($0) } ?? .secondary.opacity(0.2))
                    .frame(width: 14, height: 14)
                Text(observed.map { "Light: \($0.red), \($0.green), \($0.blue)" } ?? "Light color: Unknown")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text("Tap or drag, then release to apply.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private func pick(_ location: CGPoint) {
        let radius = diameter / 2
        let dx = location.x - radius, dy = location.y - radius
        let distance = min(hypot(dx, dy), radius)
        // Angle grows clockwise from the trailing edge, matching AngularGradient.
        let angle = atan2(dy, dx)
        let hue = (angle < 0 ? angle + 2 * .pi : angle) / (2 * .pi)
        marker = CGPoint(x: radius + cos(angle) * distance, y: radius + sin(angle) * distance)
        draft = LightColor(hue: Double(hue), saturation: Double(distance / radius))
    }
}

/// Slider that shows observed state and sends exactly one command when the drag ends.
private struct CommitSlider: View {
    let title: String
    let systemImage: String
    let range: ClosedRange<Int>
    let observed: Int?
    let unit: String
    let isEnabled: Bool
    let commit: (Int) -> Void
    @State private var draft: Double = 0
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: systemImage).font(.callout.weight(.medium))
                Spacer()
                Text(valueLabel)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(isEditing ? .primary : .secondary)
            }
            // No `step:`: macOS draws one tick mark per step, and thousands of Kelvin
            // steps put AppKit into a continuous re-layout (100% CPU/GPU). Round instead.
            Slider(value: $draft, in: Double(range.lowerBound)...Double(range.upperBound)) {
                Text(title)
            } onEditingChanged: { editing in
                isEditing = editing
                if !editing { commit(rounded) }
            }
            .labelsHidden()
            .disabled(!isEnabled)
        }
        .onAppear { syncDraft() }
        // Mirrors observed state into the draft only; it never sends a command.
        .onChange(of: observed) { _, _ in syncDraft() }
    }

    private var valueLabel: String {
        if isEditing { return "\(rounded)\(unit)" }
        return observed.map { "\($0)\(unit)" } ?? "Unknown"
    }

    private var rounded: Int {
        min(max(Int(draft.rounded()), range.lowerBound), range.upperBound)
    }

    private func syncDraft() {
        guard !isEditing else { return }
        let value = observed ?? range.lowerBound
        draft = Double(min(max(value, range.lowerBound), range.upperBound))
    }
}

private struct ReachabilityPill: View {
    let reachability: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(reachability).font(.caption)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(color.opacity(0.14), in: Capsule())
    }

    private var color: Color {
        switch reachability {
        case "Reachable": .green
        case "Unavailable": .red
        default: .orange
        }
    }
}

private extension Color {
    init(_ rgb: LightColor) {
        self.init(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }

    /// Approximate display tint for a color temperature (visual only).
    init(kelvin: Int) {
        let t = Double(min(max(kelvin, 2000), 6500) - 2000) / 4500
        self.init(red: 1, green: 0.62 + 0.33 * t, blue: 0.3 + 0.68 * t)
    }
}
