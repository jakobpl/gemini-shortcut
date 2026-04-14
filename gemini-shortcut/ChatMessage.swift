import AppKit

enum ChatRole {
    case user, model
}

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: ChatRole
    var text: String
    var image: NSImage?
    var isStreaming: Bool = false
    
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id && lhs.role == rhs.role && lhs.text == rhs.text && lhs.isStreaming == rhs.isStreaming
    }
}
