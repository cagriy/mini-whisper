import Foundation
import MWConfig

/// A dictation as it was delivered: the corrected text plus where it landed, so the menu
/// bar and the correction window can work from one value (R16, design §5.3).
public struct DeliveredDictation: Sendable, Equatable {
    public var text: String
    public var appName: String
    public var bundleID: String?
    public var engine: EngineName?
    public var deliveredAt: Date

    public init(
        text: String,
        appName: String,
        bundleID: String? = nil,
        engine: EngineName? = nil,
        deliveredAt: Date
    ) {
        self.text = text
        self.appName = appName
        self.bundleID = bundleID
        self.engine = engine
        self.deliveredAt = deliveredAt
    }
}
