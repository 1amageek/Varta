import Foundation
import Varta
import NIOCore
import PeerConnectivity

public protocol PeerConnectivityPeerResolving: Sendable {
    func resolvePeer(for address: Address) async throws -> PeerConnectivityPeer
}

public struct PeerConnectivityMailboxTransport: RemoteMailboxTransport {

    private let session: PeerConnectivitySession
    private let resolver: any PeerConnectivityPeerResolving
    private let protocolID: String

    public init(
        session: PeerConnectivitySession,
        resolver: any PeerConnectivityPeerResolving,
        protocolID: String = vartaRemoteEnvelopeProtocolID
    ) {
        self.session = session
        self.resolver = resolver
        self.protocolID = protocolID
    }

    public func deliver(
        _ request: RemoteEnvelopeDeliveryRequest
    ) async throws -> RemoteEnvelopeDeliveryResponse {
        let peer = try await resolver.resolvePeer(for: request.envelope.to)
        let channel = try await session.openChannel(to: peer, protocol: protocolID)
        do {
            try await channel.write(Self.makeBuffer(from: try P2PWireCodec.encode(request)))
            let responseBuffer = try await channel.read()
            let responseData = Data(responseBuffer.readableBytesView)
            let response = try P2PWireCodec.decodeResponse(from: responseData)
            try await channel.close()
            return response
        } catch let deliveryError {
            do {
                try await channel.close()
            } catch {
                throw deliveryError
            }
            throw deliveryError
        }
    }

    private static func makeBuffer(from data: Data) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        return buffer
    }
}
