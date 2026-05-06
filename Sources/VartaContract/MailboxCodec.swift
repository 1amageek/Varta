import Foundation

public enum MailboxCodec {

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try makeEncoder().encode(value)
    }

    public static func encode(_ envelope: Envelope) throws -> Data {
        try makeEncoder().encode(envelope)
    }

    public static func decodeEnvelope(from data: Data) throws -> Envelope {
        try makeDecoder().decode(Envelope.self, from: data)
    }

    public static func encodeRemoteRequest(_ request: RemoteEnvelopeDeliveryRequest) throws -> Data {
        try makeEncoder().encode(request)
    }

    public static func decodeRemoteRequest(from data: Data) throws -> RemoteEnvelopeDeliveryRequest {
        try makeDecoder().decode(RemoteEnvelopeDeliveryRequest.self, from: data)
    }

    public static func encodeRemoteResponse(_ response: RemoteEnvelopeDeliveryResponse) throws -> Data {
        try makeEncoder().encode(response)
    }

    public static func decodeRemoteResponse(from data: Data) throws -> RemoteEnvelopeDeliveryResponse {
        try makeDecoder().decode(RemoteEnvelopeDeliveryResponse.self, from: data)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
