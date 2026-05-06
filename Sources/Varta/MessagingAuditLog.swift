import Foundation

public struct MessagingAuditLog: Sendable {

    public let rootURLs: MessagingRootURLs

    public init(serviceRoot: URL) {
        self.rootURLs = MessagingRootURLs(root: serviceRoot)
    }

    public func append(_ event: MessagingAuditEvent) throws {
        try rootURLs.prepare()
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day], from: event.createdAt)
        let year = String(format: "%04d", components.year ?? 0)
        let month = String(format: "%02d", components.month ?? 0)
        let day = String(format: "%02d", components.day ?? 0)
        let directory = rootURLs.auditEvents
            .appendingPathComponent(year, isDirectory: true)
            .appendingPathComponent(month, isDirectory: true)
            .appendingPathComponent(day, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(event.id.uuidString).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(event).write(to: url, options: .atomic)
    }
}
