import Foundation
import SmartHomeCore

let usage = """
Usage: shl <command> [options]

Commands:
  discover [--timeout <seconds>]   Find WiZ and CozyLife devices on the local network
                                   (UDP broadcast only, default timeout 4 s)

"""

func writeError(_ text: String) {
    FileHandle.standardError.write(Data(text.utf8))
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    writeError(usage)
    exit(64)
}
arguments.removeFirst()

switch command {
case "discover":
    var timeout: TimeInterval = 4
    if let flag = arguments.firstIndex(of: "--timeout") {
        guard flag + 1 < arguments.count, let value = TimeInterval(arguments[flag + 1]), value > 0, value <= 30 else {
            writeError("error: --timeout expects a number of seconds between 0 and 30\n")
            exit(64)
        }
        timeout = value
    }
    let service = DiscoveryService.default()
    let outcome = await service.discover(timeout: timeout)
    print(DiscoveryReport.render(outcome.devices, searched: service.vendors), terminator: "")
    for (vendor, message) in outcome.failures.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
        writeError("warning: \(vendor.displayName) discovery failed: \(message)\n")
    }
    exit(outcome.failures.isEmpty ? 0 : 1)
case "-h", "--help", "help":
    print(usage, terminator: "")
default:
    writeError("error: unknown command '\(command)'\n\n" + usage)
    exit(64)
}
