import Foundation

/// A location at which a `Varta` can be reached.
///
/// `Address` is intentionally minimal: a host identifier and a path. The
/// host is a free-form string so that future transports (peer-to-peer
/// IDs, hostnames, opaque routing tokens) can fit without changing the
/// type. The path identifies a directory on the addressed host where the
/// actor's mailbox lives.
///
/// The current implementation only handles `host == "local"`, which
/// resolves `path` against the local filesystem.
public struct Address: Sendable, Codable, Hashable {

    /// Sentinel value for the local filesystem.
    public static let localHost: String = "local"

    /// The host identifier. Use `Address.localHost` for the local
    /// filesystem.
    public let host: String

    /// The directory path on the host where this actor's mailbox lives.
    /// For `host == .localHost` this is an absolute filesystem path.
    public let path: String

    public init(host: String = Address.localHost, path: String) {
        self.host = host
        self.path = path
    }

    /// Convenience constructor for an address on the local filesystem.
    public static func local(_ path: String) -> Address {
        Address(host: localHost, path: path)
    }

    /// Convenience constructor accepting a `URL`.
    public static func local(_ url: URL) -> Address {
        Address(host: localHost, path: url.path)
    }

    /// Whether this address refers to the local filesystem.
    public var isLocal: Bool { host == Self.localHost }
}
