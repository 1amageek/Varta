import Foundation

public struct MailboxRegistry: Sendable {

    public let mapper: MailboxStorageMapper

    public init(mapper: MailboxStorageMapper) {
        self.mapper = mapper
    }

    @discardableResult
    public func register(_ address: Address) throws -> MailboxRegistration {
        let urls = try mapper.mailboxURLs(for: address)
        let registrationURL = try mapper.registrationURL(for: address)
        for url in [urls.root, urls.inbox, urls.processed, urls.rejected, urls.failed] {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        }
        try FileManager.default.createDirectory(
            at: registrationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let existing = try load(address)
        let now = Date()
        let registration = MailboxRegistration(
            id: existing?.id ?? UUID(),
            address: address,
            storagePath: urls.root.path(percentEncoded: false),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(registration).write(to: registrationURL, options: .atomic)
        return registration
    }

    public func unregister(_ address: Address, deleteStorage: Bool = false) throws {
        let registrationURL = try mapper.registrationURL(for: address)
        if FileManager.default.fileExists(atPath: registrationURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: registrationURL)
        }
        if deleteStorage {
            let urls = try mapper.mailboxURLs(for: address)
            if FileManager.default.fileExists(atPath: urls.root.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: urls.root)
            }
        }
    }

    public func load(_ address: Address) throws -> MailboxRegistration? {
        let url = try mapper.registrationURL(for: address)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MailboxRegistration.self, from: Data(contentsOf: url))
    }

    public func requireRegistered(_ address: Address) throws -> MailboxURLs {
        guard try load(address) != nil else {
            throw MessagingError.mailboxNotRegistered(address)
        }
        return try mapper.mailboxURLs(for: address)
    }
}
