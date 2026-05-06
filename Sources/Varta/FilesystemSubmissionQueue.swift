import Foundation

public struct FilesystemSubmissionQueue: Sendable {

    public static let envelopeFileName = "envelope.json"
    public static let receiptFileName = "receipt.json"
    public static let failureFileName = "failure.json"

    public let root: URL
    public let pathPolicy: MailboxPathPolicy

    public init(root: URL, pathPolicy: MailboxPathPolicy = .allowAll) {
        self.root = root
        self.pathPolicy = pathPolicy
    }

    @discardableResult
    public func prepare() throws -> SubmissionQueueURLs {
        let urls = try queueURLs()
        for url in [urls.root, urls.outbox, urls.pending, urls.processing, urls.sent, urls.failed] {
            if !FileManager.default.fileExists(atPath: url.path) {
                do {
                    try FileManager.default.createDirectory(
                        at: url,
                        withIntermediateDirectories: true
                    )
                } catch {
                    throw MessagingError.invalidMailboxPath(url.path)
                }
            }
        }
        return urls
    }

    @discardableResult
    public func submit(_ envelope: Envelope) throws -> URL {
        let urls = try prepare()
        try rejectDuplicateSubmission(envelope.id, in: urls)

        let staging = urls.pending.appendingPathComponent(
            ".\(envelope.id.uuidString).tmp",
            isDirectory: true
        )
        let target = urls.pending.appendingPathComponent(
            envelope.id.uuidString,
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
            let envelopeURL = staging.appendingPathComponent(Self.envelopeFileName)
            try MailboxCodec.encode(envelope).write(to: envelopeURL, options: [.atomic])
            try FileManager.default.moveItem(at: staging, to: target)
            return target
        } catch {
            try removeStagingDirectoryIfNeeded(staging)
            throw error
        }
    }

    public func pendingEnvelopes() throws -> [QueuedEnvelope] {
        let urls = try prepare()
        let entries = try FileManager.default.contentsOfDirectory(
            at: urls.pending,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var envelopes: [QueuedEnvelope] = []
        for directory in entries {
            guard try isDirectory(directory) else { continue }
            let envelopeURL = directory.appendingPathComponent(Self.envelopeFileName)
            do {
                let envelope = try MailboxCodec.decodeEnvelope(from: Data(contentsOf: envelopeURL))
                envelopes.append(QueuedEnvelope(envelope: envelope, directory: directory))
            } catch let error as MessagingError {
                try quarantineMalformedSubmission(directory, reason: String(describing: error))
            } catch {
                let decodingError = MessagingError.envelopeDecodingFailed(
                    envelopeURL,
                    String(describing: error)
                )
                try quarantineMalformedSubmission(directory, reason: String(describing: decodingError))
            }
        }
        return envelopes.sorted { $0.envelope.issuedAt < $1.envelope.issuedAt }
    }

    public func claimNext() throws -> QueuedEnvelope? {
        guard let next = try pendingEnvelopes().first else {
            return nil
        }
        return try claim(next.id)
    }

    public func claim(_ id: UUID) throws -> QueuedEnvelope {
        let urls = try prepare()
        let source = urls.pending.appendingPathComponent(id.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw MessagingError.envelopeNotFound(id)
        }
        let destination = urls.processing.appendingPathComponent(id.uuidString, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw MessagingError.duplicateEnvelope(id)
        }
        try FileManager.default.moveItem(at: source, to: destination)
        let envelopeURL = destination.appendingPathComponent(Self.envelopeFileName)
        do {
            let envelope = try MailboxCodec.decodeEnvelope(from: Data(contentsOf: envelopeURL))
            return QueuedEnvelope(envelope: envelope, directory: destination)
        } catch let error as MessagingError {
            try quarantineMalformedSubmission(destination, reason: String(describing: error))
            throw error
        } catch {
            let decodingError = MessagingError.envelopeDecodingFailed(envelopeURL, String(describing: error))
            try quarantineMalformedSubmission(destination, reason: String(describing: decodingError))
            throw decodingError
        }
    }

    public func markSent(_ queued: QueuedEnvelope, receipt: DeliveryReceipt) throws {
        let urls = try prepare()
        let source = urls.processing.appendingPathComponent(
            queued.id.uuidString,
            isDirectory: true
        )
        let destination = urls.sent.appendingPathComponent(
            queued.id.uuidString,
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw MessagingError.envelopeNotFound(queued.id)
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw MessagingError.duplicateEnvelope(queued.id)
        }
        let receiptURL = source.appendingPathComponent(Self.receiptFileName)
        try MailboxCodec.encode(receipt).write(to: receiptURL, options: [.atomic])
        try FileManager.default.moveItem(at: source, to: destination)
    }

    @discardableResult
    public func markFailed(_ queued: QueuedEnvelope, error: any Error) throws -> SubmissionFailure {
        let urls = try prepare()
        let source = urls.processing.appendingPathComponent(
            queued.id.uuidString,
            isDirectory: true
        )
        let destination = urls.failed.appendingPathComponent(
            queued.id.uuidString,
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw MessagingError.envelopeNotFound(queued.id)
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw MessagingError.duplicateEnvelope(queued.id)
        }
        let failure = SubmissionFailure(envelopeID: queued.id, reason: String(describing: error))
        let failureURL = source.appendingPathComponent(Self.failureFileName)
        try MailboxCodec.encode(failure).write(to: failureURL, options: [.atomic])
        try FileManager.default.moveItem(at: source, to: destination)
        return failure
    }

    private func queueURLs() throws -> SubmissionQueueURLs {
        SubmissionQueueURLs(root: try pathPolicy.authorize(root.path))
    }

    private func rejectDuplicateSubmission(_ id: UUID, in urls: SubmissionQueueURLs) throws {
        let directories = [urls.pending, urls.processing, urls.sent, urls.failed]
        for directory in directories {
            let candidate = directory.appendingPathComponent(id.uuidString, isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) {
                throw MessagingError.duplicateEnvelope(id)
            }
        }
    }

    private func removeStagingDirectoryIfNeeded(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }

    private func isDirectory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true
    }

    private func quarantineMalformedSubmission(_ directory: URL, reason: String) throws {
        let quarantineRoot = MessagingRootURLs(root: root)
            .quarantineMalformed
            .appendingPathComponent("outbox", isDirectory: true)
        try FileManager.default.createDirectory(at: quarantineRoot, withIntermediateDirectories: true)
        let destination = uniqueDestination(
            in: quarantineRoot,
            basename: directory.lastPathComponent
        )
        let failure = SubmissionFailure(
            envelopeID: UUID(uuidString: directory.lastPathComponent) ?? UUID(),
            reason: reason
        )
        try MailboxCodec.encode(failure).write(
            to: directory.appendingPathComponent(Self.failureFileName),
            options: [.atomic]
        )
        try FileManager.default.moveItem(at: directory, to: destination)
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
