import Foundation

public struct MessagingGarbageCollectionReport: Sendable, Codable, Hashable {

    public let dryRun: Bool
    public let scannedCount: Int
    public let removedCount: Int
    public let candidatePaths: [String]

    public init(
        dryRun: Bool,
        scannedCount: Int,
        removedCount: Int,
        candidatePaths: [String]
    ) {
        self.dryRun = dryRun
        self.scannedCount = scannedCount
        self.removedCount = removedCount
        self.candidatePaths = candidatePaths
    }
}

public struct MessagingGarbageCollector: Sendable {

    public let rootURLs: MessagingRootURLs

    public init(serviceRoot: URL) {
        self.rootURLs = MessagingRootURLs(root: serviceRoot)
    }

    public func run(policy: MessagingRetentionPolicy, now: Date = Date()) throws -> MessagingGarbageCollectionReport {
        try rootURLs.prepare()
        var scanned = 0
        var removed = 0
        var candidates: [String] = []

        try collect(
            roots: matchingMailboxDirectories(named: "processed"),
            maxAgeSeconds: policy.processedMaxAgeSeconds,
            now: now,
            dryRun: policy.dryRun,
            scanned: &scanned,
            removed: &removed,
            candidates: &candidates
        )
        try collect(
            roots: matchingMailboxDirectories(named: "failed"),
            maxAgeSeconds: policy.failedMaxAgeSeconds,
            now: now,
            dryRun: policy.dryRun,
            scanned: &scanned,
            removed: &removed,
            candidates: &candidates
        )
        try collect(
            roots: [rootURLs.root.appendingPathComponent("outbox/sent", isDirectory: true)],
            maxAgeSeconds: policy.sentMaxAgeSeconds,
            now: now,
            dryRun: policy.dryRun,
            scanned: &scanned,
            removed: &removed,
            candidates: &candidates
        )
        try collect(
            roots: [rootURLs.root.appendingPathComponent("outbox/failed", isDirectory: true)],
            maxAgeSeconds: policy.failedMaxAgeSeconds,
            now: now,
            dryRun: policy.dryRun,
            scanned: &scanned,
            removed: &removed,
            candidates: &candidates
        )
        try collect(
            roots: [rootURLs.controlApplied],
            maxAgeSeconds: policy.controlAppliedMaxAgeSeconds,
            now: now,
            dryRun: policy.dryRun,
            scanned: &scanned,
            removed: &removed,
            candidates: &candidates
        )
        try collect(
            roots: [rootURLs.controlRejected],
            maxAgeSeconds: policy.controlRejectedMaxAgeSeconds,
            now: now,
            dryRun: policy.dryRun,
            scanned: &scanned,
            removed: &removed,
            candidates: &candidates
        )
        try collect(
            roots: [rootURLs.auditEvents],
            maxAgeSeconds: policy.auditMaxAgeSeconds,
            now: now,
            dryRun: policy.dryRun,
            scanned: &scanned,
            removed: &removed,
            candidates: &candidates
        )
        try collect(
            roots: [
                rootURLs.quarantineMalformed.appendingPathComponent("outbox", isDirectory: true),
                rootURLs.quarantineMalformed.appendingPathComponent("control", isDirectory: true),
                rootURLs.quarantineOrphaned,
                rootURLs.quarantineUnauthorized
            ],
            maxAgeSeconds: policy.quarantineMaxAgeSeconds,
            now: now,
            dryRun: policy.dryRun,
            scanned: &scanned,
            removed: &removed,
            candidates: &candidates
        )

        return MessagingGarbageCollectionReport(
            dryRun: policy.dryRun,
            scannedCount: scanned,
            removedCount: removed,
            candidatePaths: candidates.sorted()
        )
    }

    private func matchingMailboxDirectories(named name: String) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: rootURLs.mailboxes.path(percentEncoded: false)) else {
            return []
        }
        let enumerator = FileManager.default.enumerator(
            at: rootURLs.mailboxes,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        var urls: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.lastPathComponent == name else { continue }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                urls.append(url)
            }
        }
        return urls
    }

    private func collect(
        roots: [URL],
        maxAgeSeconds: TimeInterval?,
        now: Date,
        dryRun: Bool,
        scanned: inout Int,
        removed: inout Int,
        candidates: inout [String]
    ) throws {
        guard let maxAgeSeconds else {
            return
        }
        for root in roots where FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) {
            let entries = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            for entry in entries {
                scanned += 1
                let values = try entry.resourceValues(forKeys: [.contentModificationDateKey])
                let modified = values.contentModificationDate ?? Date.distantPast
                guard now.timeIntervalSince(modified) >= maxAgeSeconds else {
                    continue
                }
                candidates.append(entry.path(percentEncoded: false))
                if !dryRun {
                    try FileManager.default.removeItem(at: entry)
                    removed += 1
                }
            }
        }
    }
}
