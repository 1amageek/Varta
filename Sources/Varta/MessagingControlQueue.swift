import Foundation
import VartaContract

public struct QueuedControlCommand: Sendable, Hashable {
    public let command: MessagingControlCommand
    public let directory: URL
}

public struct MessagingControlQueue: Sendable {

    public static let commandFileName = "command.json"
    public static let resultFileName = "result.json"
    public static let failureFileName = "failure.json"

    public let urls: MessagingRootURLs

    public init(root: URL) {
        self.urls = MessagingRootURLs(root: root)
    }

    public func prepare() throws {
        try urls.prepare()
    }

    @discardableResult
    public func submit(_ command: MessagingControlCommand) throws -> URL {
        try prepare()
        let staging = urls.controlPending.appendingPathComponent(
            ".\(command.id.uuidString).tmp",
            isDirectory: true
        )
        let target = urls.controlPending.appendingPathComponent(
            command.id.uuidString,
            isDirectory: true
        )
        if FileManager.default.fileExists(atPath: staging.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: staging)
        }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(command).write(
            to: staging.appendingPathComponent(Self.commandFileName),
            options: [.atomic]
        )
        try FileManager.default.moveItem(at: staging, to: target)
        return target
    }

    public func claimNext() throws -> QueuedControlCommand? {
        try prepare()
        let entries = try FileManager.default.contentsOfDirectory(
            at: urls.controlPending,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )
        let candidates = entries.filter { $0.hasDirectoryPath }.sorted { lhs, rhs in
            lhs.lastPathComponent < rhs.lastPathComponent
        }
        for next in candidates {
            let processing = urls.controlProcessing.appendingPathComponent(
                next.lastPathComponent,
                isDirectory: true
            )
            try FileManager.default.moveItem(at: next, to: processing)
            let commandURL = processing.appendingPathComponent(Self.commandFileName)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do {
                let command = try decoder.decode(
                    MessagingControlCommand.self,
                    from: Data(contentsOf: commandURL)
                )
                return QueuedControlCommand(command: command, directory: processing)
            } catch {
                try quarantineMalformedCommand(processing, reason: String(describing: error))
                continue
            }
        }
        return nil
    }

    public func markApplied(
        _ queued: QueuedControlCommand,
        result: MessagingControlResult
    ) throws {
        let destination = urls.controlApplied.appendingPathComponent(
            queued.directory.lastPathComponent,
            isDirectory: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(result).write(
            to: queued.directory.appendingPathComponent(Self.resultFileName),
            options: [.atomic]
        )
        try FileManager.default.moveItem(at: queued.directory, to: destination)
    }

    public func markRejected(_ queued: QueuedControlCommand, error: Error) throws {
        let destination = urls.controlRejected.appendingPathComponent(
            queued.directory.lastPathComponent,
            isDirectory: true
        )
        let failure = SubmissionFailure(
            envelopeID: queued.command.id,
            reason: String(describing: error)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(failure).write(
            to: queued.directory.appendingPathComponent(Self.failureFileName),
            options: [.atomic]
        )
        try FileManager.default.moveItem(at: queued.directory, to: destination)
    }

    private func quarantineMalformedCommand(_ directory: URL, reason: String) throws {
        let quarantineRoot = urls.quarantineMalformed
            .appendingPathComponent("control", isDirectory: true)
        try FileManager.default.createDirectory(at: quarantineRoot, withIntermediateDirectories: true)
        let failure = SubmissionFailure(
            envelopeID: UUID(uuidString: directory.lastPathComponent) ?? UUID(),
            reason: reason
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(failure).write(
            to: directory.appendingPathComponent(Self.failureFileName),
            options: [.atomic]
        )
        try FileManager.default.moveItem(
            at: directory,
            to: uniqueDestination(in: quarantineRoot, basename: directory.lastPathComponent)
        )
    }

    private func uniqueDestination(in directory: URL, basename: String) -> URL {
        let first = directory.appendingPathComponent(basename, isDirectory: true)
        guard FileManager.default.fileExists(atPath: first.path(percentEncoded: false)) else {
            return first
        }
        return directory.appendingPathComponent(
            "\(basename)-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}
