import Foundation
import VartaContract

public struct SubmissionQueueURLs: Sendable, Hashable {
    public let root: URL
    public let outbox: URL
    public let pending: URL
    public let processing: URL
    public let sent: URL
    public let failed: URL

    public init(root: URL) {
        self.root = root
        self.outbox = root.appendingPathComponent("outbox", isDirectory: true)
        self.pending = outbox.appendingPathComponent("pending", isDirectory: true)
        self.processing = outbox.appendingPathComponent("processing", isDirectory: true)
        self.sent = outbox.appendingPathComponent("sent", isDirectory: true)
        self.failed = outbox.appendingPathComponent("failed", isDirectory: true)
    }
}
