import Foundation

public struct MailboxPathPolicy: Sendable, Hashable {

    public let allowedRoots: [String]

    public init(allowedRoots: [URL]) {
        self.allowedRoots = allowedRoots.map { Self.canonicalPath($0.path) }
    }

    public static var allowAll: MailboxPathPolicy {
        MailboxPathPolicy(allowedRoots: [])
    }

    public func authorize(_ path: String) throws -> URL {
        let canonical = Self.canonicalPath(path)
        guard !canonical.isEmpty else {
            throw MessagingError.invalidMailboxPath(path)
        }
        guard !canonical.contains("/../"), !canonical.hasSuffix("/..") else {
            throw MessagingError.unauthorizedPath(path)
        }
        guard !allowedRoots.isEmpty else {
            return URL(fileURLWithPath: canonical, isDirectory: true)
        }
        for root in allowedRoots {
            if canonical == root || canonical.hasPrefix(root + "/") {
                return URL(fileURLWithPath: canonical, isDirectory: true)
            }
        }
        throw MessagingError.unauthorizedPath(path)
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
            .path
    }
}
