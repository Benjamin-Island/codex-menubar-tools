import AppKit

@MainActor
protocol PasteboardWriting: AnyObject {
    func write(_ string: String)
}

@MainActor
final class SystemPasteboard: PasteboardWriting {
    func write(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
