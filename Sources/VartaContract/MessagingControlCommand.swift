import Foundation

public struct MessagingControlCommand: Sendable, Codable, Hashable, Identifiable {

    public let id: UUID
    public let issuedAt: Date
    public let kind: MessagingControlCommandKind

    public init(
        id: UUID = UUID(),
        issuedAt: Date = Date(),
        kind: MessagingControlCommandKind
    ) {
        self.id = id
        self.issuedAt = issuedAt
        self.kind = kind
    }
}

public enum MessagingControlCommandKind: Sendable, Codable, Hashable {
    case registerMailbox(address: Address)
    case unregisterMailbox(address: Address, deleteStorage: Bool)
    case runGarbageCollection(policy: MessagingRetentionPolicy)
}

public struct MessagingRetentionPolicy: Sendable, Codable, Hashable {

    public let dryRun: Bool
    public let processedMaxAgeSeconds: TimeInterval?
    public let sentMaxAgeSeconds: TimeInterval?
    public let failedMaxAgeSeconds: TimeInterval?
    public let controlAppliedMaxAgeSeconds: TimeInterval?
    public let controlRejectedMaxAgeSeconds: TimeInterval?
    public let auditMaxAgeSeconds: TimeInterval?
    public let quarantineMaxAgeSeconds: TimeInterval?

    public init(
        dryRun: Bool = true,
        processedMaxAgeSeconds: TimeInterval? = nil,
        sentMaxAgeSeconds: TimeInterval? = nil,
        failedMaxAgeSeconds: TimeInterval? = nil,
        controlAppliedMaxAgeSeconds: TimeInterval? = nil,
        controlRejectedMaxAgeSeconds: TimeInterval? = nil,
        auditMaxAgeSeconds: TimeInterval? = nil,
        quarantineMaxAgeSeconds: TimeInterval? = nil
    ) {
        self.dryRun = dryRun
        self.processedMaxAgeSeconds = processedMaxAgeSeconds
        self.sentMaxAgeSeconds = sentMaxAgeSeconds
        self.failedMaxAgeSeconds = failedMaxAgeSeconds
        self.controlAppliedMaxAgeSeconds = controlAppliedMaxAgeSeconds
        self.controlRejectedMaxAgeSeconds = controlRejectedMaxAgeSeconds
        self.auditMaxAgeSeconds = auditMaxAgeSeconds
        self.quarantineMaxAgeSeconds = quarantineMaxAgeSeconds
    }
}

public struct MessagingControlResult: Sendable, Codable, Hashable {

    public let commandID: UUID
    public let appliedAt: Date
    public let message: String

    public init(commandID: UUID, appliedAt: Date = Date(), message: String) {
        self.commandID = commandID
        self.appliedAt = appliedAt
        self.message = message
    }
}
