import AppKit
import SwiftUI

/// Native selectable text keeps long log lines scrollable and exposes their
/// actual content through the standard macOS text accessibility interface.
struct WorkflowJobLogTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView { Self.makeScrollView(text: text) }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        view.string = text
        view.scrollToBeginningOfDocument(nil)
    }

    static func makeScrollView(text: String) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let view = NSTextView(frame: .zero)
        view.isEditable = false; view.isSelectable = true; view.isRichText = false
        view.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        view.textColor = .labelColor; view.drawsBackground = false
        view.textContainerInset = NSSize(width: 12, height: 12)
        view.isHorizontallyResizable = true; view.isVerticallyResizable = true
        view.minSize = .zero; view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = view.maxSize
        view.autoresizingMask = [.width]
        view.string = text
        scroll.documentView = view
        return scroll
    }
}
