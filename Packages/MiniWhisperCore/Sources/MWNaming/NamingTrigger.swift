/// Times are meeting seconds passed in by the caller, so the trigger holds no clock.
public struct NamingTrigger: Sendable {
    public static let defaultDelay: Double = 20

    public private(set) var inFlight = false
    private let delay: Double
    private var armed: (speaker: Int, deadline: Double)?
    private var followUp = false

    public init(delay: Double = NamingTrigger.defaultDelay) {
        self.delay = delay
    }

    public mutating func segment(speaker: Int, hasName: Bool, at time: Double) -> Bool {
        var fires = false
        if let armed, armed.speaker != speaker {
            self.armed = nil
            fires = fire()
        }
        // An armed trigger keeps its first deadline, so a run of names from one speaker
        // cannot keep pushing the request back.
        if hasName, armed == nil {
            armed = (speaker, time + delay)
        }
        return fires
    }

    public mutating func tick(at time: Double) -> Bool {
        guard let armed, time >= armed.deadline else { return false }
        self.armed = nil
        return fire()
    }

    public mutating func begin() {
        inFlight = true
    }

    public mutating func end() -> Bool {
        defer { followUp = false }
        inFlight = false
        return followUp
    }

    public mutating func disarm() {
        armed = nil
        followUp = false
    }

    private mutating func fire() -> Bool {
        if inFlight { followUp = true }
        return !inFlight
    }
}
