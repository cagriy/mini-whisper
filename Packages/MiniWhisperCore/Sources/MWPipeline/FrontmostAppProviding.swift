/// `NSWorkspace.shared.frontmostApplication` behind a seam: the profile and the paste
/// target are resolved from it at release time (F17).
public protocol FrontmostAppProviding: Sendable {
    func frontmost() -> PasteTarget?
}
