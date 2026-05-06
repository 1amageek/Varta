import Foundation

public enum AddressHost: Sendable, Hashable {
    case local
    case peer(String)
    case device(String)
    case unsupported(String)
}

public extension Address {

    static let peerPrefix = "peer:"
    static let devicePrefix = "device:"

    var hostKind: AddressHost {
        if host == Self.localHost {
            return .local
        }
        if host.hasPrefix(Self.peerPrefix) {
            return .peer(String(host.dropFirst(Self.peerPrefix.count)))
        }
        if host.hasPrefix(Self.devicePrefix) {
            return .device(String(host.dropFirst(Self.devicePrefix.count)))
        }
        return .unsupported(host)
    }

    static func peer(_ peerID: String, path: String) -> Address {
        Address(host: "\(peerPrefix)\(peerID)", path: path)
    }

    static func device(_ stableName: String, path: String) -> Address {
        Address(host: "\(devicePrefix)\(stableName)", path: path)
    }
}
