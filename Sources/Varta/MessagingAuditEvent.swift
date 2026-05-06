import Foundation
import VartaContract

public struct MessagingAuditEvent: Sendable, Codable, Hashable, Identifiable {

    public let id: UUID
    public let kind: String
    public let message: String
    public let createdAt: Date
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        kind: String,
        message: String,
        createdAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.createdAt = createdAt
        self.metadata = metadata
    }
}
