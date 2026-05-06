import Foundation
import VartaContract

public struct LocalFilesystemMailbox: Sendable {

    public let pathPolicy: MailboxPathPolicy
    public let serviceRoot: URL

    private var mapper: MailboxStorageMapper {
        MailboxStorageMapper(serviceRoot: serviceRoot, pathPolicy: pathPolicy)
    }

    private var registry: MailboxRegistry {
        MailboxRegistry(mapper: mapper)
    }

    public init(
        serviceRoot: URL = Varta.defaultServiceRoot(),
        pathPolicy: MailboxPathPolicy = .allowAll
    ) {
        self.serviceRoot = serviceRoot
        self.pathPolicy = pathPolicy
    }

    @discardableResult
    public func prepareMailbox(at address: Address) throws -> MailboxURLs {
        guard address.isLocal else {
            throw MessagingError.unsupportedHost(address.host)
        }
        return try registerMailbox(at: address)
    }

    @discardableResult
    public func registerMailbox(at address: Address) throws -> MailboxURLs {
        _ = try registry.register(address)
        return try mapper.mailboxURLs(for: address)
    }

    public func deliver(_ envelope: Envelope) throws -> DeliveryReceipt {
        guard envelope.to.isLocal else {
            throw MessagingError.unsupportedHost(envelope.to.host)
        }
        try store(envelope, at: envelope.to, requireRegistration: true)
        return DeliveryReceipt(envelopeID: envelope.id, mode: .local)
    }

    public func storeRemote(_ envelope: Envelope) throws -> DeliveryReceipt {
        try store(envelope, at: .local(envelope.to.path), requireRegistration: true)
        return DeliveryReceipt(envelopeID: envelope.id, mode: .remote)
    }

    public func receive(at address: Address) throws -> [Envelope] {
        guard address.isLocal else {
            throw MessagingError.unsupportedHost(address.host)
        }
        let urls = try mailboxURLs(for: address)
        let entries = try FileManager.default.contentsOfDirectory(
            at: urls.inbox,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var envelopes: [Envelope] = []
        for url in entries where url.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: url)
                envelopes.append(try MailboxCodec.decodeEnvelope(from: data))
            } catch let error as MessagingError {
                throw error
            } catch {
                throw MessagingError.envelopeDecodingFailed(url, String(describing: error))
            }
        }
        return envelopes.sorted { $0.issuedAt < $1.issuedAt }
    }

    public func ack(_ id: UUID, at address: Address) throws {
        guard address.isLocal else {
            throw MessagingError.unsupportedHost(address.host)
        }
        let urls = try mailboxURLs(for: address)
        let source = urls.inbox.appendingPathComponent("\(id.uuidString).json")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw MessagingError.envelopeNotFound(id)
        }
        let destination = urls.processed.appendingPathComponent("\(id.uuidString).json")
        if FileManager.default.fileExists(atPath: destination.path) {
            throw MessagingError.duplicateEnvelope(id)
        }
        try FileManager.default.moveItem(at: source, to: destination)
    }

    private func store(
        _ envelope: Envelope,
        at address: Address,
        requireRegistration: Bool
    ) throws {
        let urls = requireRegistration
            ? try registry.requireRegistered(address)
            : try mapper.mailboxURLs(for: address)
        let target = urls.inbox.appendingPathComponent("\(envelope.id.uuidString).json")
        let processed = urls.processed.appendingPathComponent("\(envelope.id.uuidString).json")
        guard !FileManager.default.fileExists(atPath: target.path),
              !FileManager.default.fileExists(atPath: processed.path) else {
            throw MessagingError.duplicateEnvelope(envelope.id)
        }

        let staging = urls.inbox.appendingPathComponent(".\(envelope.id.uuidString).json.tmp")
        do {
            let data = try MailboxCodec.encode(envelope)
            try data.write(to: staging, options: [.atomic])
            try FileManager.default.moveItem(at: staging, to: target)
        } catch {
            if FileManager.default.fileExists(atPath: staging.path) {
                do {
                    try FileManager.default.removeItem(at: staging)
                } catch {
                    throw MessagingError.invalidMailboxPath(staging.path)
                }
            }
            throw error
        }
    }

    private func mailboxURLs(for address: Address) throws -> MailboxURLs {
        try registry.requireRegistered(address)
    }
}
