import SwiftUI
import AppKit

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("Paragraph 1").font(.body)
            Text("Paragraph 2").font(.body)
            Text("Paragraph 3").font(.body)
        }
        .textSelection(.enabled)
        .padding()
    }
}

let view = ContentView()
