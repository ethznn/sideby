public enum ImmediateSwipeCommandAdmission {
    @discardableResult
    public static func admit(
        _ command: SwitchCommand,
        latch: inout InputCommandLatch,
        at timestamp: Double
    ) -> Bool {
        latch.beginSwitch(command, source: .swipe, at: timestamp)
    }
}
