import Foundation

public struct MailboxStorageMapper: Sendable, Hashable {

    public let serviceRoot: URL
    public let pathPolicy: MailboxPathPolicy

    private var rootURLs: MessagingRootURLs {
        MessagingRootURLs(root: serviceRoot)
    }

    public init(
        serviceRoot: URL = MessagingDefaults.defaultServiceRoot(),
        pathPolicy: MailboxPathPolicy = .allowAll
    ) {
        self.serviceRoot = serviceRoot
        self.pathPolicy = pathPolicy
    }

    public func mailboxURLs(for address: Address) throws -> MailboxURLs {
        switch address.hostKind {
        case .local:
            return MailboxURLs(root: try storageRoot(forLocalPath: address.path))
        case .peer(let peerID):
            return MailboxURLs(root: try storageRoot(forRemotePath: address.path, namespace: "peers", owner: peerID))
        case .device(let deviceName):
            return MailboxURLs(root: try storageRoot(forRemotePath: address.path, namespace: "devices", owner: deviceName))
        case .unsupported(let host):
            throw MessagingError.unsupportedHost(host)
        }
    }

    public func localMailboxURLs(for path: String) throws -> MailboxURLs {
        MailboxURLs(root: try storageRoot(forLocalPath: path))
    }

    public func registrationURL(for address: Address) throws -> URL {
        let urls = try mailboxURLs(for: address)
        return rootURLs.mailboxRegistry
            .appendingPathComponent(relativeMirrorPath(from: urls.root), isDirectory: true)
            .appendingPathComponent("registration.json")
    }

    private func storageRoot(forLocalPath path: String) throws -> URL {
        let canonical = try pathPolicy.authorize(path)
        return rootURLs.mailboxes
            .appendingPathComponent("local", isDirectory: true)
            .appendingPathComponent(mirrorPath(for: canonical), isDirectory: true)
    }

    private func storageRoot(
        forRemotePath path: String,
        namespace: String,
        owner: String
    ) throws -> URL {
        guard !owner.isEmpty else {
            throw MessagingError.unsupportedHost(namespace)
        }
        let canonical = URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
        return rootURLs.mailboxes
            .appendingPathComponent(namespace, isDirectory: true)
            .appendingPathComponent(owner, isDirectory: true)
            .appendingPathComponent(mirrorPath(for: canonical), isDirectory: true)
    }

    private func mirrorPath(for url: URL) -> String {
        url.pathComponents
            .filter { $0 != "/" && !$0.isEmpty }
            .joined(separator: "/")
    }

    private func relativeMirrorPath(from storageRoot: URL) -> String {
        let base = rootURLs.mailboxes.path(percentEncoded: false)
        let path = storageRoot.path(percentEncoded: false)
        guard path.hasPrefix(base + "/") else {
            return storageRoot.lastPathComponent
        }
        return String(path.dropFirst(base.count + 1))
    }

}
