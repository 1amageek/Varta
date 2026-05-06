import Foundation

enum MailboxCodec {

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try makeEncoder().encode(value)
    }

    static func encode(_ envelope: Envelope) throws -> Data {
        try makeEncoder().encode(envelope)
    }

    static func decodeEnvelope(from data: Data) throws -> Envelope {
        try makeDecoder().decode(Envelope.self, from: data)
    }

    static func encodeRemoteRequest(_ request: RemoteEnvelopeDeliveryRequest) throws -> Data {
        try makeEncoder().encode(request)
    }

    static func decodeRemoteRequest(from data: Data) throws -> RemoteEnvelopeDeliveryRequest {
        try makeDecoder().decode(RemoteEnvelopeDeliveryRequest.self, from: data)
    }

    static func encodeRemoteResponse(_ response: RemoteEnvelopeDeliveryResponse) throws -> Data {
        try makeEncoder().encode(response)
    }

    static func decodeRemoteResponse(from data: Data) throws -> RemoteEnvelopeDeliveryResponse {
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
