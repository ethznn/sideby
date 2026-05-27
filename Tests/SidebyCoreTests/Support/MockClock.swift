struct MockClock {
    private(set) var now: Double

    init(start: Double = 0) {
        self.now = start
    }

    mutating func advance(by interval: Double) {
        now += interval
    }
}
