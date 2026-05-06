import Foundation
import Varta
import VartaP2P
import NIOCore
import PeerConnectivity
import Testing

@Suite("PeerConnectivity mailbox transport")
struct PeerConnectivityMailboxTransportTests {

    @Test("transport writes request bytes and decodes delivery response")
    func transportRoundTrip() async throws {
        let peer = PeerConnectivityPeer(id: "peer-1", displayName: "Peer 1")
        let envelope = Envelope(
            from: .local("/sender"),
            to: .peer("peer-1", path: "/remote/mailbox"),
            issuedAt: Date(timeIntervalSince1970: 1_900_000_000),
            mediaType: "text/plain",
            data: Data("hello".utf8)
        )
        let response = RemoteEnvelopeDeliveryResponse(
            envelopeID: envelope.id,
            accepted: true,
            storedAt: Date(timeIntervalSince1970: 2_000)
        )
        let channel = FakePeerConnectivityChannel(
            peer: peer,
            protocolID: vartaRemoteEnvelopeProtocolID,
            response: response
        )
        let backend = FakePeerConnectivityBackend(channel: channel)
        let session = PeerConnectivitySession(backend: backend)
        let transport = PeerConnectivityMailboxTransport(
            session: session,
            resolver: StaticPeerResolver(peer: peer)
        )

        let delivered = try await transport.deliver(
            RemoteEnvelopeDeliveryRequest(envelope: envelope)
        )

        #expect(delivered == response)
        #expect(await channel.closeCount == 1)
        let written = try await channel.decodeWrittenRequest()
        #expect(written.envelope == envelope)
    }
}

private struct StaticPeerResolver: PeerConnectivityPeerResolving {
    let peer: PeerConnectivityPeer

    func resolvePeer(for address: Address) async throws -> PeerConnectivityPeer {
        guard address.hostKind == .peer(peer.id) else {
            throw MessagingError.unsupportedHost(address.host)
        }
        return peer
    }
}

private actor FakePeerConnectivityBackend: PeerConnectivityBackend {
    nonisolated let capabilities: PeerConnectivityCapabilities = [
        .messageSend,
        .streamMultiplexing
    ]
    nonisolated let events: AsyncStream<PeerConnectivityEvent>

    private let channel: FakePeerConnectivityChannel

    init(channel: FakePeerConnectivityChannel) {
        self.channel = channel
        self.events = AsyncStream { continuation in
            continuation.finish()
        }
    }

    func start() async throws {}

    func shutdown() async throws {}

    func connect(to endpoint: PeerConnectivityEndpoint) async throws -> PeerConnectivityPeer {
        throw PeerConnectivityError.unsupportedEndpoint(endpoint)
    }

    func disconnect(from peer: PeerConnectivityPeer) async throws {}

    func send(
        _ bytes: ByteBuffer,
        to peer: PeerConnectivityPeer,
        mode: PeerSendMode
    ) async throws {}

    func openChannel(
        to peer: PeerConnectivityPeer,
        protocol protocolID: String
    ) async throws -> any PeerConnectivityChannel {
        channel
    }

    func sendResource(_ resource: PeerResource, to peer: PeerConnectivityPeer) async throws {
        throw PeerConnectivityError.unsupportedOperation("sendResource")
    }
}

private actor FakePeerConnectivityChannel: PeerConnectivityChannel {
    nonisolated let peer: PeerConnectivityPeer
    nonisolated let protocolID: String?

    private let response: RemoteEnvelopeDeliveryResponse
    private var written: [ByteBuffer] = []
    private(set) var closeCount = 0

    init(
        peer: PeerConnectivityPeer,
        protocolID: String,
        response: RemoteEnvelopeDeliveryResponse
    ) {
        self.peer = peer
        self.protocolID = protocolID
        self.response = response
    }

    func read() async throws -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        let data = try makeEncoder().encode(response)
        buffer.writeBytes(data)
        return buffer
    }

    func write(_ bytes: ByteBuffer) async throws {
        written.append(bytes)
    }

    func close() async throws {
        closeCount += 1
    }

    func decodeWrittenRequest() throws -> RemoteEnvelopeDeliveryRequest {
        let buffer = try #require(written.first)
        let data = Data(buffer.readableBytesView)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RemoteEnvelopeDeliveryRequest.self, from: data)
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
