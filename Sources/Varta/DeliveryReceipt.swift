import Foundation

public enum DeliveryMode: String, Sendable, Codable, Hashable {
    case local
    case remote
}

public struct DeliveryReceipt: Sendable, Codable, Hashable {
    public let envelopeID: UUID
    public let mode: DeliveryMode
    public let storedAt: Date

    public init(envelopeID: UUID, mode: DeliveryMode, storedAt: Date = Date()) {
        self.envelopeID = envelopeID
        self.mode = mode
        self.storedAt = storedAt
    }
}
