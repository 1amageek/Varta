import Foundation

public let vartaRemoteEnvelopeProtocolID = "/bioid/varta/envelope/1"

public struct RemoteEnvelopeDeliveryRequest: Sendable, Codable, Hashable {
    public let envelope: Envelope
    public let requestedAt: Date

    public init(envelope: Envelope, requestedAt: Date = Date()) {
        self.envelope = envelope
        self.requestedAt = requestedAt
    }
}

public struct RemoteEnvelopeDeliveryResponse: Sendable, Codable, Hashable {
    public let envelopeID: UUID
    public let accepted: Bool
    public let storedAt: Date?
    public let error: RemoteEnvelopeDeliveryError?

    public init(
        envelopeID: UUID,
        accepted: Bool,
        storedAt: Date? = nil,
        error: RemoteEnvelopeDeliveryError? = nil
    ) {
        self.envelopeID = envelopeID
        self.accepted = accepted
        self.storedAt = storedAt
        self.error = error
    }
}

public enum RemoteEnvelopeDeliveryError: String, Sendable, Codable, Hashable {
    case unsupportedHost
    case unknownPeer
    case unauthorizedPath
    case invalidPath
    case duplicateEnvelope
    case decodingFailed
    case storageFailed
}

public protocol RemoteMailboxTransport: Sendable {
    func deliver(_ request: RemoteEnvelopeDeliveryRequest) async throws -> RemoteEnvelopeDeliveryResponse
}
