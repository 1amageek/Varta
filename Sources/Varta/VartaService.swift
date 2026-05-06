import Foundation

public actor VartaService {

    private let localMailbox: LocalFilesystemMailbox

    public init(
        serviceRoot: URL = Varta.defaultServiceRoot(),
        allowedMailboxRoots: [URL]
    ) {
        self.localMailbox = LocalFilesystemMailbox(
            serviceRoot: serviceRoot,
            pathPolicy: MailboxPathPolicy(allowedRoots: allowedMailboxRoots)
        )
    }

    public init(
        serviceRoot: URL = Varta.defaultServiceRoot(),
        pathPolicy: MailboxPathPolicy = .allowAll
    ) {
        self.localMailbox = LocalFilesystemMailbox(
            serviceRoot: serviceRoot,
            pathPolicy: pathPolicy
        )
    }

    public func acceptRemoteDelivery(
        _ request: RemoteEnvelopeDeliveryRequest
    ) async -> RemoteEnvelopeDeliveryResponse {
        do {
            let receipt = try localMailbox.storeRemote(request.envelope)
            return RemoteEnvelopeDeliveryResponse(
                envelopeID: receipt.envelopeID,
                accepted: true,
                storedAt: receipt.storedAt
            )
        } catch MessagingError.unauthorizedPath {
            return RemoteEnvelopeDeliveryResponse(
                envelopeID: request.envelope.id,
                accepted: false,
                error: .unauthorizedPath
            )
        } catch MessagingError.duplicateEnvelope {
            return RemoteEnvelopeDeliveryResponse(
                envelopeID: request.envelope.id,
                accepted: false,
                error: .duplicateEnvelope
            )
        } catch MessagingError.invalidMailboxPath {
            return RemoteEnvelopeDeliveryResponse(
                envelopeID: request.envelope.id,
                accepted: false,
                error: .invalidPath
            )
        } catch {
            return RemoteEnvelopeDeliveryResponse(
                envelopeID: request.envelope.id,
                accepted: false,
                error: .storageFailed
            )
        }
    }
}
