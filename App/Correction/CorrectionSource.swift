import Foundation
import MWHistory
import MWPipeline

/// What the correction window was opened from: one transcript, where it was delivered
/// and whether the whole of it is the phrase (design §5.1).
struct CorrectionSource: Equatable {
    var text: String
    var appName: String?
    var bundleID: String?
    /// `EngineName.rawValue` as stored, so the window's source line reuses
    /// `HistoryListModel.engineLabel` rather than re-deriving the labels.
    var engine: String?
    var deliveredAt: Date?
    /// True for a phrase that is its own transcript — the Settings tally's Remember… (R35).
    var preselectAll: Bool

    init(
        text: String,
        appName: String? = nil,
        bundleID: String? = nil,
        engine: String? = nil,
        deliveredAt: Date? = nil,
        preselectAll: Bool = false
    ) {
        self.text = text
        self.appName = appName
        self.bundleID = bundleID
        self.engine = engine
        self.deliveredAt = deliveredAt
        self.preselectAll = preselectAll
    }

    init(_ dictation: DeliveredDictation) {
        self.init(
            text: dictation.text,
            appName: dictation.appName,
            bundleID: dictation.bundleID,
            engine: dictation.engine?.rawValue,
            deliveredAt: dictation.deliveredAt
        )
    }

    init(_ entry: HistoryEntry) {
        self.init(
            text: entry.text,
            appName: entry.appName,
            bundleID: entry.bundleID,
            engine: entry.engine,
            deliveredAt: entry.timestamp
        )
    }

    init(phrase: String) {
        self.init(text: phrase, preselectAll: true)
    }
}
