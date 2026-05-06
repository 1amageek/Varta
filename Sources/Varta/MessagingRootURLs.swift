import Foundation

public struct MessagingRootURLs: Sendable, Hashable {

    public let root: URL
    public let mailboxes: URL
    public let registry: URL
    public let mailboxRegistry: URL
    public let control: URL
    public let controlPending: URL
    public let controlProcessing: URL
    public let controlApplied: URL
    public let controlRejected: URL
    public let audit: URL
    public let auditEvents: URL
    public let quarantine: URL
    public let quarantineMalformed: URL
    public let quarantineOrphaned: URL
    public let quarantineUnauthorized: URL

    public init(root: URL) {
        self.root = root
        self.mailboxes = root.appendingPathComponent("mailboxes", isDirectory: true)
        self.registry = root.appendingPathComponent("registry", isDirectory: true)
        self.mailboxRegistry = registry.appendingPathComponent("mailboxes", isDirectory: true)
        self.control = root.appendingPathComponent("control", isDirectory: true)
        self.controlPending = control.appendingPathComponent("pending", isDirectory: true)
        self.controlProcessing = control.appendingPathComponent("processing", isDirectory: true)
        self.controlApplied = control.appendingPathComponent("applied", isDirectory: true)
        self.controlRejected = control.appendingPathComponent("rejected", isDirectory: true)
        self.audit = root.appendingPathComponent("audit", isDirectory: true)
        self.auditEvents = audit.appendingPathComponent("events", isDirectory: true)
        self.quarantine = root.appendingPathComponent("quarantine", isDirectory: true)
        self.quarantineMalformed = quarantine.appendingPathComponent("malformed", isDirectory: true)
        self.quarantineOrphaned = quarantine.appendingPathComponent("orphaned", isDirectory: true)
        self.quarantineUnauthorized = quarantine.appendingPathComponent("unauthorized", isDirectory: true)
    }

    public func prepare() throws {
        for url in [
            root,
            mailboxes,
            registry,
            mailboxRegistry,
            control,
            controlPending,
            controlProcessing,
            controlApplied,
            controlRejected,
            audit,
            auditEvents,
            quarantine,
            quarantineMalformed,
            quarantineOrphaned,
            quarantineUnauthorized
        ] {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        }
    }
}
