import Foundation

public struct MailboxURLs: Sendable, Hashable {
    public let root: URL
    public let inbox: URL
    public let processed: URL
    public let rejected: URL
    public let failed: URL

    public init(root: URL) {
        self.root = root
        self.inbox = self.root.appendingPathComponent("inbox", isDirectory: true)
        self.processed = self.root.appendingPathComponent("processed", isDirectory: true)
        self.rejected = self.root.appendingPathComponent("rejected", isDirectory: true)
        self.failed = self.root.appendingPathComponent("failed", isDirectory: true)
    }
}
