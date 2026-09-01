import MWConfig

/// One day's accumulated usage. The config file's `usage` values are exactly this
/// shape, so the stored type is reused rather than mirrored.
public typealias DayEntry = DayUsage
