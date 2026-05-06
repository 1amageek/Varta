import Foundation

public struct MailboxRegistration: Sendable, Codable, Hashable, Identifiable {

    public let id: UUID
    public let address: Address
    public let storagePath: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID = UUID(),
        address: Address,
        storagePath: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.address = address
        self.storagePath = storagePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
