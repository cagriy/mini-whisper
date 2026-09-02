import AppKit
import MWPaste

/// `NSPasteboard.general` behind F25's seam. A snapshot keeps every item and type so a
/// restore puts back exactly what was there.
struct NSPasteboardAccess: PasteboardAccess {
    func snapshot() -> PasteboardSnapshot {
        let items = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            item.types.reduce(into: [String: Data]()) { types, type in
                types[type.rawValue] = item.data(forType: type)
            }
        }
        return PasteboardSnapshot(items: items)
    }

    func write(_ text: String) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    var changeCount: Int { NSPasteboard.general.changeCount }

    func restore(_ snapshot: PasteboardSnapshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let items = snapshot.items.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
            return item
        }
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }
}
