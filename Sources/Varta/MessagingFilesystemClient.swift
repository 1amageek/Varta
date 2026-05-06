import Foundation

/// Filesystem client for non-owner processes.
///
/// This client only writes producer-owned contract paths:
/// `control/pending` and `outbox/pending`. It can also read and acknowledge
/// the caller's mailbox after the daemon has registered and created it.
public struct MessagingFilesystemClient: Sendable {

    public let serviceRoot: URL
    public let pathPolicy: MailboxPathPolicy

    private var mapper: MailboxStorageMapper {
        MailboxStorageMapper(serviceRoot: serviceRoot, pathPolicy: pathPolicy)
    }

    public init(
        serviceRoot: URL = Varta.defaultServiceRoot(),
        pathPolicy: MailboxPathPolicy = .allowAll
    ) {
        self.serviceRoot = serviceRoot
        self.pathPolicy = pathPolicy
    }

    @discardableResult
    public func registerMailbox(_ address: Address) throws -> URL {
        try submitControl(MessagingControlCommand(kind: .registerMailbox(address: address)))
    }

    @discardableResult
    public func unregisterMailbox(_ address: Address, deleteStorage: Bool = false) throws -> URL {
        try submitControl(MessagingControlCommand(
            kind: .unregisterMailbox(address: address, deleteStorage: deleteStorage)
        ))
    }

    @discardableResult
    public func submitControl(_ command: MessagingControlCommand) throws -> URL {
        let pending = serviceRoot
            .appendingPathComponent("control", isDirectory: true)
            .appendingPathComponent("pending", isDirectory: true)
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
        let staging = pending.appendingPathComponent(".\(command.id.uuidString).tmp", isDirectory: true)
        let target = pending.appendingPathComponent(command.id.uuidString, isDirectory: true)
        return try writeAtomically(
            value: command,
            fileName: MessagingControlQueue.commandFileName,
            staging: staging,
            target: target
        )
    }

    @discardableResult
    public func submit(_ envelope: Envelope) throws -> URL {
        let pending = serviceRoot
            .appendingPathComponent("outbox", isDirectory: true)
            .appendingPathComponent("pending", isDirectory: true)
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
        let staging = pending.appendingPathComponent(".\(envelope.id.uuidString).tmp", isDirectory: true)
        let target = pending.appendingPathComponent(envelope.id.uuidString, isDirectory: true)
        return try writeAtomically(
            value: envelope,
            fileName: FilesystemSubmissionQueue.envelopeFileName,
            staging: staging,
            target: target
        )
    }

    public func receive(at address: Address) throws -> [Envelope] {
        guard address.isLocal else {
            throw MessagingError.unsupportedHost(address.host)
        }
        let urls = try mapper.mailboxURLs(for: address)
        guard FileManager.default.fileExists(atPath: urls.inbox.path(percentEncoded: false)) else {
            return []
        }
        let entries = try FileManager.default.contentsOfDirectory(
            at: urls.inbox,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var envelopes: [Envelope] = []
        for entry in entries where entry.pathExtension == "json" {
            do {
                envelopes.append(try MailboxCodec.decodeEnvelope(from: Data(contentsOf: entry)))
            } catch let error as MessagingError {
                throw error
            } catch {
                throw MessagingError.envelopeDecodingFailed(entry, String(describing: error))
            }
        }
        return envelopes.sorted { $0.issuedAt < $1.issuedAt }
    }

    public func ack(_ id: UUID, at address: Address) throws {
        guard address.isLocal else {
            throw MessagingError.unsupportedHost(address.host)
        }
        let urls = try mapper.mailboxURLs(for: address)
        let source = urls.inbox.appendingPathComponent("\(id.uuidString).json")
        guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else {
            throw MessagingError.envelopeNotFound(id)
        }
        let destination = urls.processed.appendingPathComponent("\(id.uuidString).json")
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            throw MessagingError.duplicateEnvelope(id)
        }
        try FileManager.default.moveItem(at: source, to: destination)
    }

    private func writeAtomically<T: Encodable>(
        value: T,
        fileName: String,
        staging: URL,
        target: URL
    ) throws -> URL {
        if FileManager.default.fileExists(atPath: staging.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: staging)
        }
        guard !FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) else {
            guard let duplicateID = UUID(uuidString: target.lastPathComponent) else {
                throw MessagingError.invalidMailboxPath(target.path(percentEncoded: false))
            }
            throw MessagingError.duplicateEnvelope(duplicateID)
        }
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
            try MailboxCodec.encode(value).write(
                to: staging.appendingPathComponent(fileName),
                options: [.atomic]
            )
            try FileManager.default.moveItem(at: staging, to: target)
            return target
        } catch {
            if FileManager.default.fileExists(atPath: staging.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: staging)
            }
            throw error
        }
    }
}
