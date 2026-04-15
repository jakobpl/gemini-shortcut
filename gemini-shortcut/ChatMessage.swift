import AppKit
import Foundation

enum ChatRole: String, Codable {
    case user, model
}

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    var text: String
    var image: NSImage?          // user-attached image (not persisted)
    var generatedImages: [Data]  // AI-generated image PNG data (persisted)
    var isStreaming: Bool
    let timestamp: Date

    init(
        id: UUID = UUID(),
        role: ChatRole,
        text: String,
        image: NSImage? = nil,
        isStreaming: Bool = false,
        generatedImages: [Data] = [],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.image = image
        self.generatedImages = generatedImages
        self.isStreaming = isStreaming
        self.timestamp = timestamp
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id &&
        lhs.text == rhs.text &&
        lhs.isStreaming == rhs.isStreaming &&
        lhs.generatedImages.count == rhs.generatedImages.count
    }
}

// MARK: - Persistence helper (no NSImage)

struct PersistedMessage: Codable {
    let id: String
    let role: String
    let text: String
    let generatedImages: [Data]
    let timestamp: Double   // timeIntervalSince1970
}
