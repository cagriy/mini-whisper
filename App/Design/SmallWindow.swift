import AppKit
import SwiftUI

extension NSWindow {
    /// Correction, Onboarding or About: a fixed-size window with a standard title bar on the canvas.
    /// `size` is the whole window, title bar included, as the mockups measure it.
    static func small(title: String, size: CGSize, closable: Bool = true) -> NSWindow {
        let style: NSWindow.StyleMask = closable ? [.titled, .closable] : [.titled]
        let window = NSWindow(
            contentRect: contentRect(forFrameRect: CGRect(origin: .zero, size: size), styleMask: style),
            styleMask: style,
            backing: .buffered,
            defer: true
        )
        window.title = title
        window.titlebarAppearsTransparent = true
        window.backgroundColor = DS.Colors.canvas.nsColor
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    /// Makes `view` the window's content. The content never resizes the window; with `fit`, the
    /// window first takes the content's size, its top edge where it was.
    @discardableResult
    func host<Content: View>(_ view: Content, fit: Bool = false) -> NSHostingView<Content> {
        let host = NSHostingView(rootView: view)
        if fit {
            // Measured first: once it stops sizing the window, a hosting view reports no fitting size.
            let top = frame.maxY
            setContentSize(host.fittingSize)
            setFrameTopLeftPoint(CGPoint(x: frame.minX, y: top))
        }
        host.sizingOptions = []
        contentView = host
        return host
    }
}

extension View {
    /// A small window's content: inset under its title bar and filling the window.
    func smallWindowBody(_ alignment: Alignment = .topLeading, top: CGFloat = DS.Space.s3) -> some View {
        padding(EdgeInsets(top: top, leading: 20, bottom: DS.Space.s8, trailing: 20))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .background(DS.Colors.canvas)
    }
}
