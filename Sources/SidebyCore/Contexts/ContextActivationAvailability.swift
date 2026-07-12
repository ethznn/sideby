public enum ContextActivationAvailability: Sendable {
    public static func canActivate(
        isSidebyEnabled: Bool,
        isSwitching: Bool,
        isCapturing: Bool
    ) -> Bool {
        isSidebyEnabled && !isSwitching && !isCapturing
    }
}
