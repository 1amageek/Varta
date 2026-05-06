import Foundation
import Varta

@main
struct VartaDaemonCommand {

    static func main() async {
        do {
            let options = try DaemonOptions(arguments: Array(CommandLine.arguments.dropFirst()))
            try await run(options: options)
        } catch DaemonError.helpRequested {
            print(Self.helpText)
        } catch {
            FileHandle.standardError.write(Data("vartad: \(error)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func run(options: DaemonOptions) async throws {
        let daemon = try await Varta(serviceRoot: options.serviceRoot)
        try writePID(to: options.pidFile)
        defer {
            removePID(at: options.pidFile)
        }

        FileHandle.standardError.write(
            Data("vartad: started serviceRoot=\(options.serviceRoot.path)\n".utf8)
        )

        if options.once {
            _ = try await daemon.processControlCommands()
            _ = try await daemon.processPending()
            return
        }

        while true {
            try Task.checkCancellation()
            _ = try await daemon.processControlCommands()
            _ = try await daemon.processPending()
            try await Task.sleep(for: options.pollInterval)
        }
    }

    private static func writePID(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("\(getpid())\n".utf8).write(to: url, options: [.atomic])
    }

    private static func removePID(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            FileHandle.standardError.write(
                Data("vartad: failed to remove pid file: \(error)\n".utf8)
            )
        }
    }

    private static let helpText = """
    Usage: vartad [--service-root PATH] [--pid-file PATH] [--poll-ms N] [--once]

    Watches the Varta filesystem submission outbox and routes
    pending envelopes to local mailboxes. Remote envelopes require a
    configured remote transport and otherwise remain in failed/.
    """
}

private struct DaemonOptions: Sendable {
    let serviceRoot: URL
    let pidFile: URL
    let pollInterval: Duration
    let once: Bool

    init(arguments: [String]) throws {
        var serviceRoot: URL?
        var pidFile: URL?
        var pollMilliseconds = 250
        var once = false

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--help", "-h":
                throw DaemonError.helpRequested
            case "--service-root":
                serviceRoot = URL(
                    fileURLWithPath: try Self.value(after: argument, in: arguments, at: &index),
                    isDirectory: true
                )
            case "--pid-file":
                pidFile = URL(fileURLWithPath: try Self.value(after: argument, in: arguments, at: &index))
            case "--poll-ms":
                let value = try Self.value(after: argument, in: arguments, at: &index)
                guard let parsed = Int(value), parsed > 0 else {
                    throw DaemonError.invalidArgument("--poll-ms must be a positive integer")
                }
                pollMilliseconds = parsed
            case "--once":
                once = true
            default:
                throw DaemonError.invalidArgument("unknown argument: \(argument)")
            }
            index += 1
        }

        let resolvedServiceRoot = serviceRoot ?? Self.defaultServiceRoot()
        self.serviceRoot = resolvedServiceRoot
        self.pidFile = pidFile ?? resolvedServiceRoot
            .appendingPathComponent("run", isDirectory: true)
            .appendingPathComponent("vartad.pid")
        self.pollInterval = .milliseconds(pollMilliseconds)
        self.once = once
    }

    private static func value(
        after option: String,
        in arguments: [String],
        at index: inout Int
    ) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw DaemonError.invalidArgument("\(option) requires a value")
        }
        index = valueIndex
        return arguments[valueIndex]
    }

    private static func defaultServiceRoot() -> URL {
        Varta.defaultServiceRoot()
    }
}

private enum DaemonError: Error, CustomStringConvertible {
    case helpRequested
    case invalidArgument(String)

    var description: String {
        switch self {
        case .helpRequested:
            return "help requested"
        case .invalidArgument(let message):
            return message
        }
    }
}
