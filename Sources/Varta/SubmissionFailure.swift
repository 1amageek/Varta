import Foundation

public struct SubmissionFailure: Sendable, Codable, Hashable {
    public let envelopeID: UUID
    public let failedAt: Date
    public let reason: String

    public init(envelopeID: UUID, failedAt: Date = Date(), reason: String) {
        self.envelopeID = envelopeID
        self.failedAt = failedAt
        self.reason = reason
    }
}
