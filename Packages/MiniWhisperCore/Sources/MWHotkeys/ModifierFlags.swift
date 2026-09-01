/// macOS `CGEventFlags` subset used for matching (design §5.4).
public struct ModifierFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) { self.rawValue = rawValue }

    public static let shift = ModifierFlags(rawValue: 0x20000)
    public static let control = ModifierFlags(rawValue: 0x40000)
    public static let option = ModifierFlags(rawValue: 0x80000)
    public static let command = ModifierFlags(rawValue: 0x100000)

    public init(_ modifiers: some Sequence<Modifier>) {
        self = modifiers.reduce(into: []) { $0.formUnion($1.flag) }
    }

    public var modifiers: Set<Modifier> {
        Set(Modifier.allCases.filter { contains($0.flag) })
    }
}

extension Modifier {
    public var flag: ModifierFlags {
        switch self {
        case .alt: .option
        case .cmd: .command
        case .ctrl: .control
        case .shift: .shift
        }
    }
}
