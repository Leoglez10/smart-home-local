/// A driver with verified metadata used by the protocol-agnostic command session.
public struct SessionDevice: Sendable {
    public let device: any SmartDevice
    public let temperatureRange: ClosedRange<Int>?

    public init(_ device: any SmartDevice, temperatureRange: ClosedRange<Int>? = nil) {
        self.device = device
        self.temperatureRange = temperatureRange
    }
}

/// Separate output streams let the executable preserve errors when stdin is piped.
public struct SessionResponse: Equatable, Sendable {
    public let output: String
    public let error: String?
    public let shouldQuit: Bool

    public init(output: String = "", error: String? = nil, shouldQuit: Bool = false) {
        self.output = output
        self.error = error
        self.shouldQuit = shouldQuit
    }
}

/// Command parsing and validation are independent of vendor protocols and network I/O.
public struct DeviceSession {
    public static let help = """
    Commands:
      devices                 List controllable devices
      select <number>         Select a device from the numbered list
      on | off                Change power
      brightness <0...100>    Set brightness percent
      color <r> <g> <b>       Set RGB channels (0...255)
      temperature <kelvin>   Set verified color temperature
      status                  Read real device state
      help                    Show commands
      quit                    Exit

    """

    private let devices: [SessionDevice]
    private var selectedIndex: Int?

    public init(devices: [SessionDevice]) {
        self.devices = devices
    }

    public mutating func execute(_ line: String) async -> SessionResponse {
        let command: Command
        do {
            command = try Command.parse(line)
        } catch let error as CommandError {
            return SessionResponse(error: "error: \(error.message)\n")
        } catch {
            return SessionResponse(error: "error: \(error)\n")
        }

        switch command {
        case .empty:
            return SessionResponse()
        case .devices:
            var output = "Devices\n"
            if devices.isEmpty { output += "(no controllable devices found)\n" }
            for (index, entry) in devices.enumerated() {
                let device = entry.device
                output += "\(index + 1). [\(device.vendor.displayName)] \(device.name) | ID: \(device.id) | Address: \(device.address)\n"
            }
            return SessionResponse(output: output)
        case .select(let number):
            // Validate without subtracting first: even Int.min cannot overflow here.
            guard number > 0, number <= devices.count else {
                return SessionResponse(error: "error: device number out of range\n")
            }
            selectedIndex = number - 1
            let device = devices[number - 1].device
            return SessionResponse(output: "Selected \(number): [\(device.vendor.displayName)] \(device.name) (\(device.id))\n")
        case .help:
            return SessionResponse(output: Self.help)
        case .quit:
            return SessionResponse(output: "Bye.\n", shouldQuit: true)
        default:
            break
        }

        guard let selectedIndex else {
            return SessionResponse(error: "error: no device selected; use select <number>\n")
        }
        let entry = devices[selectedIndex]
        let device = entry.device
        if let required = command.requiredCapability, !device.capabilities.contains(required) {
            return SessionResponse(error: "error: selected device does not support \(command.name)\n")
        }
        if case .temperature(let kelvin) = command {
            guard let range = entry.temperatureRange else {
                return SessionResponse(error: "error: verified temperature range unavailable\n")
            }
            guard range.contains(kelvin) else {
                return SessionResponse(error: "error: temperature must be between \(range.lowerBound) and \(range.upperBound) K\n")
            }
        }

        do {
            switch command {
            case .on: try await device.turnOn()
            case .off: try await device.turnOff()
            case .brightness(let percent): try await device.setBrightness(percent)
            case .color(let color): try await device.setColor(color)
            case .temperature(let kelvin): try await device.setColorTemperature(kelvin)
            default: break
            }
            // An ACK is not a state snapshot. Always read back, including after setters.
            return SessionResponse(output: Self.render(try await device.getState()))
        } catch {
            // A timeout, bad response, or failed write cannot establish current reachability.
            return SessionResponse(error: "error: device request failed (reachability unconfirmed): \(error)\n")
        }
    }

    private static func render(_ state: DeviceState) -> String {
        let power = state.isOn.map { $0 ? "ON" : "OFF" } ?? "unknown"
        let brightness = state.brightness.map { "\($0)%" } ?? "unknown"
        let color = state.color.map { "\($0.red) \($0.green) \($0.blue)" } ?? "unknown"
        let temperature = state.colorTemperature.map { "\($0) K" } ?? "unknown"
        return "Reachability: reachable\nState: \(power)\nBrightness: \(brightness)\nColor: \(color)\nTemperature: \(temperature)\n"
    }
}

private struct CommandError: Error {
    let message: String
}

private enum Command {
    case empty, devices, select(Int), on, off, brightness(Int), color(RGBColor)
    case temperature(Int), status, help, quit

    var name: String {
        switch self {
        case .on: "on"
        case .off: "off"
        case .brightness: "brightness"
        case .color: "color"
        case .temperature: "temperature"
        default: ""
        }
    }

    var requiredCapability: DeviceCapabilities? {
        switch self {
        case .on, .off: .power
        case .brightness: .brightness
        case .color: .color
        case .temperature: .colorTemperature
        default: nil
        }
    }

    static func parse(_ line: String) throws -> Command {
        let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let name = tokens.first else { return .empty }
        let arguments = Array(tokens.dropFirst())
        switch name {
        case "devices", "on", "off", "status", "help", "quit":
            guard arguments.isEmpty else { throw CommandError(message: "usage: \(name)") }
            switch name {
            case "devices": return .devices
            case "on": return .on
            case "off": return .off
            case "status": return .status
            case "help": return .help
            default: return .quit
            }
        case "select", "brightness", "temperature":
            let usage: String
            switch name {
            case "select": usage = "select <number>"
            case "brightness": usage = "brightness <0...100>"
            default: usage = "temperature <kelvin>"
            }
            guard arguments.count == 1, let value = Int(arguments[0]) else {
                throw CommandError(message: "usage: \(usage)")
            }
            switch name {
            case "select": return .select(value)
            case "brightness":
                guard (0...100).contains(value) else {
                    throw CommandError(message: "brightness must be between 0 and 100")
                }
                return .brightness(value)
            default:
                guard value > 0 else { throw CommandError(message: "temperature must be positive") }
                return .temperature(value)
            }
        case "color":
            guard arguments.count == 3,
                  let red = Int(arguments[0]), let green = Int(arguments[1]), let blue = Int(arguments[2]) else {
                throw CommandError(message: "usage: color <r> <g> <b>")
            }
            guard [red, green, blue].allSatisfy({ (0...255).contains($0) }) else {
                throw CommandError(message: "color channels must be between 0 and 255")
            }
            return .color(RGBColor(red: red, green: green, blue: blue))
        default:
            throw CommandError(message: "unknown command '\(name)'")
        }
    }
}
