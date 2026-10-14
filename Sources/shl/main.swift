import Foundation
import SmartHomeCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

let usage = """
Usage: shl <command> [options]

Commands:
  discover [--timeout <seconds>]   Find WiZ and CozyLife devices on the local network
                                   (UDP broadcast only, default timeout 4 s)
  devices                         Find WiZ devices and start a command session
                                   (CozyLife is discover-only; no control)
  help | --help | -h               Show this help

Device session:
""" + "\n" + DeviceSession.help

func writeOutput(_ text: String) {
    FileHandle.standardOutput.write(Data(text.utf8))
}

func writeError(_ text: String) {
    FileHandle.standardError.write(Data(text.utf8))
}

/// Reject the entire argument vector before constructing discovery services or drivers.
enum Invocation {
    case discover(TimeInterval)
    case devices
    case help

    static func parse(_ arguments: [String]) throws -> Invocation {
        guard let command = arguments.first else { throw ArgumentError(message: nil) }
        let options = Array(arguments.dropFirst())
        switch command {
        case "discover":
            if options.isEmpty { return .discover(4) }
            guard options.first == "--timeout", options.count <= 2 else {
                throw ArgumentError(message: "usage: shl discover [--timeout <seconds>]")
            }
            guard options.count == 2, let timeout = TimeInterval(options[1]),
                  timeout.isFinite, timeout > 0, timeout <= 30 else {
                throw ArgumentError(message: "--timeout expects a finite number of seconds greater than 0 and at most 30")
            }
            return .discover(timeout)
        case "devices":
            guard options.isEmpty else { throw ArgumentError(message: "usage: shl devices") }
            return .devices
        case "-h", "--help", "help":
            guard options.isEmpty else { throw ArgumentError(message: "help accepts no extra arguments") }
            return .help
        default:
            throw ArgumentError(message: "unknown command '\(command)'")
        }
    }
}

struct ArgumentError: Error {
    let message: String?
}

let invocation: Invocation
do {
    invocation = try Invocation.parse(Array(CommandLine.arguments.dropFirst()))
} catch let error as ArgumentError {
    if let message = error.message { writeError("error: \(message)\n\n") }
    writeError(usage)
    exit(64)
} catch {
    writeError("error: \(error)\n")
    exit(64)
}

switch invocation {
case .help:
    writeOutput(usage)
case .discover(let timeout):
    let service = DiscoveryService.default()
    let outcome = await service.discover(timeout: timeout)
    writeOutput(DiscoveryReport.render(outcome.devices, searched: service.vendors))
    for (vendor, message) in outcome.failures.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
        writeError("warning: \(vendor.displayName) discovery failed: \(message)\n")
    }
    exit(outcome.failures.isEmpty ? 0 : 1)
case .devices:
    // This entry point deliberately never discovers or connects a CozyLife control driver.
    let service = DiscoveryService(providers: [WiZDiscoveryProvider()])
    let outcome = await service.discover(timeout: 4)
    for (vendor, message) in outcome.failures.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
        writeError("warning: \(vendor.displayName) discovery failed: \(message)\n")
    }
    var connected: [SessionDevice] = []
    for discovered in outcome.devices {
        do {
            let device = try await WiZDevice.connect(discovered)
            connected.append(SessionDevice(device, temperatureRange: device.temperatureRange))
        } catch {
            writeError("warning: WiZ device \(discovered.identifier) at \(discovered.address) unavailable: \(error)\n")
        }
    }
    var session = DeviceSession(devices: connected)
    writeOutput(await session.execute("devices").output)
    writeOutput("Use select <number>, then help for commands. CozyLife is discover-only.\n")
    let interactive = isatty(STDIN_FILENO) != 0
    while true {
        if interactive { writeOutput("> ") }
        guard let line = readLine() else { break }
        let response = await session.execute(line)
        writeOutput(response.output)
        if let error = response.error { writeError(error) }
        if response.shouldQuit { break }
    }
}
