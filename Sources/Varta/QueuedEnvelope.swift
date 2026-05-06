import Foundation
import VartaContract

public struct QueuedEnvelope: Sendable, Hashable, Identifiable {
    public var id: UUID { envelope.id }
    public let envelope: Envelope
    public let directory: URL

    public init(envelope: Envelope, directory: URL) {
        self.envelope = envelope
        self.directory = directory
    }
}
