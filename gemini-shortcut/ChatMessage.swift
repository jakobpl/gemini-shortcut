import AppKit
import Foundation

enum ChatRole: String, Codable {
    case user, model
}

enum MessageRating: String, Codable {
    case positive, negative
}

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    var text: String
    var image: NSImage?          // user-attached image (not persisted)
    var generatedImages: [Data]  // AI-generated image PNG data (persisted)
    var isStreaming: Bool
    var rating: MessageRating?   // user feedback (persisted)
    var revealedCharCount: Int   // for fade-in streaming text animation
    let timestamp: Date

    init(
        id: UUID = UUID(),
        role: ChatRole,
        text: String,
        image: NSImage? = nil,
        isStreaming: Bool = false,
        generatedImages: [Data] = [],
        rating: MessageRating? = nil,
        revealedCharCount: Int = 0,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.image = image
        self.generatedImages = generatedImages
        self.isStreaming = isStreaming
        self.rating = rating
        self.revealedCharCount = revealedCharCount
        self.timestamp = timestamp
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id &&
        lhs.text == rhs.text &&
        lhs.isStreaming == rhs.isStreaming &&
        lhs.generatedImages.count == rhs.generatedImages.count &&
        lhs.rating == rhs.rating &&
        lhs.revealedCharCount == rhs.revealedCharCount
    }
}

// MARK: - Persistence helper (no NSImage)

struct PersistedMessage: Codable {
    let id: String
    let role: String
    let text: String
    let generatedImages: [Data]
    let timestamp: Double   // timeIntervalSince1970
    let rating: String?     // "positive" or "negative"
}
