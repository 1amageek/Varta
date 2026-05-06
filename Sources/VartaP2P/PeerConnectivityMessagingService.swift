import Foundation
import Varta
import NIOCore
import PeerConnectivity

public actor PeerConnectivityMessagingService {

    private let session: PeerConnectivitySession
    private let mailboxService: VartaService
    private let protocolID: String
    private var servingTask: Task<Void, Never>?

    public init(
        session: PeerConnectivitySession,
        mailboxService: VartaService,
        protocolID: String = vartaRemoteEnvelopeProtocolID
    ) {
        self.session = session
        self.mailboxService = mailboxService
        self.protocolID = protocolID
    }

    public func start() {
        guard servingTask == nil else { return }
        let events = session.events
        let protocolID = protocolID
        let mailboxService = mailboxService
        servingTask = Task {
            for await event in events {
                guard case .channelOpened(let channel) = event,
                      channel.protocolID == protocolID else {
                    continue
                }
                await Self.handle(channel: channel, mailboxService: mailboxService)
            }
        }
    }

    public func shutdown() async {
        servingTask?.cancel()
        servingTask = nil
    }

    private static func handle(
        channel: any PeerConnectivityChannel,
        mailboxService: VartaService
    ) async {
        do {
            let requestBuffer = try await channel.read()
            let requestData = Data(requestBuffer.readableBytesView)
            let request = try P2PWireCodec.decodeRequest(from: requestData)
            let response = await mailboxService.acceptRemoteDelivery(request)
            try await channel.write(makeBuffer(from: try P2PWireCodec.encode(response)))
            try await channel.close()
        } catch {
            do {
                try await channel.close()
            } catch {
                return
            }
        }
    }

    private static func makeBuffer(from data: Data) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        return buffer
    }
}
