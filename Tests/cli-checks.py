"""Public executable regressions: help and rejected arguments only, never valid discovery.

No live-device fixtures, IPs, transport mocks, or external dependencies are used.
The first check fails safely against the pre-control executable's old help text.
"""
import subprocess
import sys

USAGE = """Usage: shl <command> [options]

Commands:
  discover [--timeout <seconds>]   Find WiZ and CozyLife devices on the local network
                                   (UDP broadcast only, default timeout 4 s)
  devices                         Find WiZ devices and start a command session
                                   (CozyLife is discover-only; no control)
  help | --help | -h               Show this help

Device session:
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


def check(binary, arguments, code, stdout, stderr):
    result = subprocess.run(
        [binary, *arguments], input="quit\n", capture_output=True,
        text=True, timeout=2, check=False,
    )
    actual = (result.returncode, result.stdout, result.stderr)
    expected = (code, stdout, stderr)
    assert actual == expected, f"{arguments!r}: expected {expected!r}, got {actual!r}"


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: python3 -I Tests/cli-checks.py <shl-executable>")
    binary = sys.argv[1]
    checks = 0
    # Help is socket-free even in the old executable; observe its RED first.
    for help_argument in ["--help", "-h", "help"]:
        check(binary, [help_argument], 0, USAGE, "")
        checks += 1
    check(binary, [], 64, "", USAGE)
    checks += 1
    check(binary, ["unknown"], 64, "", "error: unknown command 'unknown'\n\n" + USAGE)
    checks += 1
    for arguments in [
        ["devices", "extra"], ["devices", "--timeout", "4"],
        ["--help", "extra"], ["-h", "extra"], ["help", "extra"],
        ["discover", "extra"], ["discover", "--help"],
        ["discover", "--timeout", "1", "extra"],
        ["discover", "extra", "--timeout", "1"],
        ["discover", "--timeout", "1", "--timeout", "1"],
        ["discover", "--timeot", "1"], ["discover", "--timeout=1"],
    ]:
        command = arguments[0]
        if command == "devices":
            error = "usage: shl devices"
        elif command == "discover":
            error = "usage: shl discover [--timeout <seconds>]"
        else:
            error = "help accepts no extra arguments"
        check(binary, arguments, 64, "", "error: " + error + "\n\n" + USAGE)
        checks += 1
    for arguments in [["discover", "--timeout"]] + [
        ["discover", "--timeout", value]
        for value in ["0", "-1", "30.0001", "31", "nan", "inf", "-inf", "Infinity", "1e309", "oops", ""]
    ]:
        check(binary, arguments, 64, "",
              "error: --timeout expects a finite number of seconds greater than 0 and at most 30\n\n" + USAGE)
        checks += 1
    print(f"PASS: {checks} CLI argument checks (help/rejections only)")


if __name__ == "__main__":
    main()
