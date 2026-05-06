import Foundation

/// Errors raised by `Varta`.
///
/// Errors are surfaced explicitly rather than swallowed: callers must
/// decide whether to retry, escalate, or drop. There is no silent
/// fallback for delivery, decoding, or addressing failures.
public enum MessagingError: Sendable, Error, Hashable {

    /// The address refers to a transport this implementation does not
    /// support (currently anything other than `host == .localHost`).
    case unsupportedHost(String)

    /// The envelope addressed to or read from a path that does not
    /// resolve to a usable directory.
    case invalidMailboxPath(String)

    /// No envelope with the given id exists in the mailbox the
    /// operation targeted.
    case envelopeNotFound(UUID)

    /// The on-disk envelope file could not be decoded into an
    /// `Envelope` value.
    case envelopeDecodingFailed(URL, String)

    /// An envelope with the same id already exists in durable mailbox
    /// state.
    case duplicateEnvelope(UUID)

    /// A path was rejected by mailbox root policy.
    case unauthorizedPath(String)

    /// The address has not been registered as a mailbox.
    case mailboxNotRegistered(Address)

    /// A persisted control command could not be decoded or applied.
    case controlCommandFailed(UUID, String)

    /// No remote transport was configured for a non-local recipient.
    case remoteTransportUnavailable(String)

    /// The remote peer rejected delivery.
    case remoteDeliveryRejected(UUID, RemoteEnvelopeDeliveryError)

    /// The remote peer returned a response for a different envelope id.
    case mismatchedRemoteDeliveryResponse(expected: UUID, actual: UUID)
}
