import Foundation

/// A unit of message exchanged between `Varta` instances.
///
/// `Envelope` carries an opaque payload labelled with a `mediaType`,
/// together with the metadata needed to route, audit, and chain the
/// message:
///
/// - `from`/`to` — the sender and recipient addresses
/// - `causality` — the chain of envelope ids that produced this one,
///   parallel to the causality chain used in Symbio messages
/// - `mediaType` — open vocabulary, mirrors `Stimulus.mediaType`
///
/// `Envelope` is intentionally agnostic about delivery semantics. The
/// actor decides where to write it; persistence and delivery are the
/// actor's responsibility.
public struct Envelope: Sendable, Codable, Hashable, Identifiable {

    public let id: UUID
    public let from: Address
    public let to: Address
    public let issuedAt: Date
    public let causality: [UUID]
    public let mediaType: String
    public let data: Data
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        from: Address,
        to: Address,
        issuedAt: Date = Date(),
        causality: [UUID] = [],
        mediaType: String,
        data: Data,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.from = from
        self.to = to
        self.issuedAt = issuedAt
        self.causality = causality
        self.mediaType = mediaType
        self.data = data
        self.metadata = metadata
    }
}
