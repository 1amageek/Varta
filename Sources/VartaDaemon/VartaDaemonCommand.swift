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
        let echoService = options.e2eEchoAddress.map { address in
            VartaEchoService(address: address, serviceRoot: options.serviceRoot)
        }
        if let e2eEchoAddress = options.e2eEchoAddress {
            _ = try await daemon.registerMailbox(e2eEchoAddress)
        }

        try writePID(to: options.pidFile)
        defer {
            removePID(at: options.pidFile)
        }

        FileHandle.standardError.write(
            Data("vartad: started serviceRoot=\(options.serviceRoot.path)\n".utf8)
        )

        if options.once {
            try await processCycle(daemon: daemon, echoService: echoService)
            return
        }

        while true {
            try Task.checkCancellation()
            try await processCycle(daemon: daemon, echoService: echoService)
            try await Task.sleep(for: options.pollInterval)
        }
    }

    private static func processCycle(
        daemon: Varta,
        echoService: VartaEchoService?
    ) async throws {
        _ = try await daemon.processControlCommands()
        _ = try await daemon.processPending()

        guard let echoService else { return }
        let replies = try echoService.process()
        if !replies.isEmpty {
            _ = try await daemon.processPending()
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
    Usage: vartad [--service-root PATH] [--pid-file PATH] [--poll-ms N] [--once] [--e2e-echo PATH]

    Watches the Varta filesystem submission outbox and routes
    pending envelopes to local mailboxes. Remote envelopes require a
    configured remote transport and otherwise remain in failed/.

    --e2e-echo registers a local mailbox at PATH and replies to every
    received envelope with the same payload. It is intended for daemon
    end-to-end tests that must not depend on an agent runtime.
    """
}

private struct DaemonOptions: Sendable {
    let serviceRoot: URL
    let pidFile: URL
    let pollInterval: Duration
    let once: Bool
    let e2eEchoAddress: Address?

    init(arguments: [String]) throws {
        var serviceRoot: URL?
        var pidFile: URL?
        var pollMilliseconds = 250
        var once = false
        var e2eEchoAddress: Address?

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
            case "--e2e-echo":
                let path = try Self.value(after: argument, in: arguments, at: &index)
                e2eEchoAddress = .local(path)
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
        self.e2eEchoAddress = e2eEchoAddress
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
