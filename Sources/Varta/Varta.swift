import Foundation

/// Filesystem submission daemon and local mailbox reader.
public actor Varta {

    public let address: Address
    public let serviceRoot: URL

    private let localMailbox: LocalFilesystemMailbox
    private let submissionQueue: FilesystemSubmissionQueue
    private let controlQueue: MessagingControlQueue
    private let mailboxRegistry: MailboxRegistry
    private let auditLog: MessagingAuditLog
    private let garbageCollector: MessagingGarbageCollector
    private let remoteTransport: (any RemoteMailboxTransport)?

    public static func defaultServiceRoot() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Messaging", isDirectory: true)
    }

    public init(
        address: Address,
        serviceRoot: URL? = nil,
        remoteTransport: (any RemoteMailboxTransport)? = nil,
        pathPolicy: MailboxPathPolicy = .allowAll
    ) async throws {
        guard address.isLocal else {
            throw MessagingError.unsupportedHost(address.host)
        }
        self.address = address
        self.serviceRoot = serviceRoot ?? Self.defaultServiceRoot()
        let mapper = MailboxStorageMapper(serviceRoot: self.serviceRoot, pathPolicy: pathPolicy)
        self.localMailbox = LocalFilesystemMailbox(
            serviceRoot: self.serviceRoot,
            pathPolicy: pathPolicy
        )
        self.submissionQueue = FilesystemSubmissionQueue(
            root: self.serviceRoot,
            pathPolicy: pathPolicy
        )
        self.controlQueue = MessagingControlQueue(root: self.serviceRoot)
        self.mailboxRegistry = MailboxRegistry(mapper: mapper)
        self.auditLog = MessagingAuditLog(serviceRoot: self.serviceRoot)
        self.garbageCollector = MessagingGarbageCollector(serviceRoot: self.serviceRoot)
        self.remoteTransport = remoteTransport
        try MessagingRootURLs(root: self.serviceRoot).prepare()
        try localMailbox.prepareMailbox(at: address)
        try submissionQueue.prepare()
        try controlQueue.prepare()
    }

    public init(
        serviceRoot: URL,
        remoteTransport: (any RemoteMailboxTransport)? = nil,
        pathPolicy: MailboxPathPolicy = .allowAll
    ) async throws {
        self.address = .local(serviceRoot.path)
        self.serviceRoot = serviceRoot
        let mapper = MailboxStorageMapper(serviceRoot: serviceRoot, pathPolicy: pathPolicy)
        self.localMailbox = LocalFilesystemMailbox(
            serviceRoot: serviceRoot,
            pathPolicy: pathPolicy
        )
        self.submissionQueue = FilesystemSubmissionQueue(
            root: serviceRoot,
            pathPolicy: pathPolicy
        )
        self.controlQueue = MessagingControlQueue(root: serviceRoot)
        self.mailboxRegistry = MailboxRegistry(mapper: mapper)
        self.auditLog = MessagingAuditLog(serviceRoot: serviceRoot)
        self.garbageCollector = MessagingGarbageCollector(serviceRoot: serviceRoot)
        self.remoteTransport = remoteTransport
        try MessagingRootURLs(root: serviceRoot).prepare()
        try submissionQueue.prepare()
        try controlQueue.prepare()
    }

    @discardableResult
    public func submit(_ envelope: Envelope) throws -> URL {
        try submissionQueue.submit(envelope)
    }

    @discardableResult
    public func submitControl(_ command: MessagingControlCommand) throws -> URL {
        try controlQueue.submit(command)
    }

    @discardableResult
    public func registerMailbox(_ address: Address) throws -> MailboxRegistration {
        try mailboxRegistry.register(address)
    }

    public func mailboxURLs(for address: Address) throws -> MailboxURLs {
        try mailboxRegistry.requireRegistered(address)
    }

    @discardableResult
    public func processControlCommands(limit: Int? = nil) throws -> [MessagingControlResult] {
        var results: [MessagingControlResult] = []
        var processedCount = 0
        while limit.map({ processedCount < $0 }) ?? true {
            guard let queued = try controlQueue.claimNext() else {
                break
            }
            processedCount += 1
            do {
                let result = try apply(queued.command)
                try controlQueue.markApplied(queued, result: result)
                try auditLog.append(MessagingAuditEvent(
                    kind: "control.applied",
                    message: result.message,
                    metadata: ["commandID": queued.command.id.uuidString]
                ))
                results.append(result)
            } catch {
                try controlQueue.markRejected(queued, error: error)
                try auditLog.append(MessagingAuditEvent(
                    kind: "control.rejected",
                    message: String(describing: error),
                    metadata: ["commandID": queued.command.id.uuidString]
                ))
            }
        }
        return results
    }

    @discardableResult
    public func processPending(limit: Int? = nil) async throws -> [DeliveryReceipt] {
        try await processPending(limit: limit, stopOnFailure: false)
    }

    @discardableResult
    private func processPending(
        limit: Int? = nil,
        stopOnFailure: Bool
    ) async throws -> [DeliveryReceipt] {
        var receipts: [DeliveryReceipt] = []
        var processedCount = 0
        while limit.map({ processedCount < $0 }) ?? true {
            guard let queued = try submissionQueue.claimNext() else {
                break
            }
            processedCount += 1
            do {
                let receipt = try await route(queued.envelope)
                try submissionQueue.markSent(queued, receipt: receipt)
                try auditLog.append(MessagingAuditEvent(
                    kind: "delivery.sent",
                    message: "delivered envelope \(queued.id.uuidString)",
                    metadata: [
                        "envelopeID": queued.id.uuidString,
                        "to": queued.envelope.to.path
                    ]
                ))
                receipts.append(receipt)
            } catch {
                try submissionQueue.markFailed(queued, error: error)
                try auditLog.append(MessagingAuditEvent(
                    kind: "delivery.failed",
                    message: String(describing: error),
                    metadata: [
                        "envelopeID": queued.id.uuidString,
                        "to": queued.envelope.to.path
                    ]
                ))
                if stopOnFailure {
                    throw error
                }
            }
        }
        return receipts
    }

    @discardableResult
    public func send(_ envelope: Envelope) async throws -> DeliveryReceipt {
        try submit(envelope)
        let receipts = try await processPending(stopOnFailure: true)
        guard let receipt = receipts.first(where: { $0.envelopeID == envelope.id }) else {
            throw MessagingError.envelopeNotFound(envelope.id)
        }
        return receipt
    }

    private func route(_ envelope: Envelope) async throws -> DeliveryReceipt {
        switch envelope.to.hostKind {
        case .local:
            return try localMailbox.deliver(envelope)
        case .peer, .device:
            guard let remoteTransport else {
                throw MessagingError.remoteTransportUnavailable(envelope.to.host)
            }
            let response = try await remoteTransport.deliver(
                RemoteEnvelopeDeliveryRequest(envelope: envelope)
            )
            guard response.envelopeID == envelope.id else {
                throw MessagingError.mismatchedRemoteDeliveryResponse(
                    expected: envelope.id,
                    actual: response.envelopeID
                )
            }
            guard response.accepted else {
                throw MessagingError.remoteDeliveryRejected(
                    envelope.id,
                    response.error ?? .storageFailed
                )
            }
            return DeliveryReceipt(
                envelopeID: response.envelopeID,
                mode: .remote,
                storedAt: response.storedAt ?? Date()
            )
        case .unsupported(let host):
            throw MessagingError.unsupportedHost(host)
        }
    }

    private func apply(_ command: MessagingControlCommand) throws -> MessagingControlResult {
        switch command.kind {
        case .registerMailbox(let address):
            _ = try mailboxRegistry.register(address)
            return MessagingControlResult(
                commandID: command.id,
                message: "registered mailbox \(address.host):\(address.path)"
            )
        case .unregisterMailbox(let address, let deleteStorage):
            try mailboxRegistry.unregister(address, deleteStorage: deleteStorage)
            return MessagingControlResult(
                commandID: command.id,
                message: "unregistered mailbox \(address.host):\(address.path)"
            )
        case .runGarbageCollection(let policy):
            let report = try garbageCollector.run(policy: policy)
            try auditLog.append(MessagingAuditEvent(
                kind: "gc.completed",
                message: "garbage collection scanned \(report.scannedCount), removed \(report.removedCount)",
                metadata: [
                    "dryRun": "\(report.dryRun)",
                    "scannedCount": "\(report.scannedCount)",
                    "removedCount": "\(report.removedCount)"
                ]
            ))
            return MessagingControlResult(
                commandID: command.id,
                message: "garbage collection scanned \(report.scannedCount), removed \(report.removedCount)"
            )
        }
    }

    /// Snapshot every envelope currently in this actor's `inbox/`.
    public func receive() throws -> [Envelope] {
        try localMailbox.receive(at: address)
    }

    public func ack(_ id: UUID) throws {
        try localMailbox.ack(id, at: address)
    }
}
