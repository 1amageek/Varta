import Foundation
import Varta

enum P2PWireCodec {

    static func encode(_ request: RemoteEnvelopeDeliveryRequest) throws -> Data {
        try makeEncoder().encode(request)
    }

    static func decodeRequest(from data: Data) throws -> RemoteEnvelopeDeliveryRequest {
        try makeDecoder().decode(RemoteEnvelopeDeliveryRequest.self, from: data)
    }

    static func encode(_ response: RemoteEnvelopeDeliveryResponse) throws -> Data {
        try makeEncoder().encode(response)
    }

    static func decodeResponse(from data: Data) throws -> RemoteEnvelopeDeliveryResponse {
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
