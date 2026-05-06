import Foundation
import VartaContract

public struct VartaEchoService: Sendable {

    public let address: Address
    public let serviceRoot: URL
    public let pathPolicy: MailboxPathPolicy

    private let client: MessagingFilesystemClient

    public init(
        address: Address,
        serviceRoot: URL,
        pathPolicy: MailboxPathPolicy = .allowAll
    ) {
        self.address = address
        self.serviceRoot = serviceRoot
        self.pathPolicy = pathPolicy
        self.client = MessagingFilesystemClient(
            serviceRoot: serviceRoot,
            pathPolicy: pathPolicy
        )
    }

    @discardableResult
    public func process(limit: Int? = nil) throws -> [Envelope] {
        let received = try client.receive(at: address)
        let maxCount = Swift.max(0, limit ?? received.count)
        let requests = Array(received.prefix(maxCount))
        var replies: [Envelope] = []

        for request in requests {
            if request.metadata[Metadata.echoKind] == Metadata.replyKind {
                try client.ack(request.id, at: address)
                continue
            }

            let reply = makeReply(to: request)
            try client.submit(reply)
            try client.ack(request.id, at: address)
            replies.append(reply)
        }

        return replies
    }

    private func makeReply(to request: Envelope) -> Envelope {
        var metadata = request.metadata
        metadata[Metadata.echoKind] = Metadata.replyKind
        metadata[Metadata.inReplyTo] = request.id.uuidString

        return Envelope(
            from: address,
            to: request.from,
            causality: request.causality + [request.id],
            mediaType: request.mediaType,
            data: request.data,
            metadata: metadata
        )
    }
}

private enum Metadata {

    static let echoKind = "varta.e2eEcho.kind"
    static let replyKind = "reply"
    static let inReplyTo = "messaging.inReplyTo"
}
