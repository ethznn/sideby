public enum SpaceCaptureStatusDisplay {
    public static func statusText(
        currentSpace: Int,
        totalSpaces: Int,
        strings: SBSStrings
    ) -> String {
        strings.capturingSpace(current: currentSpace, total: totalSpaces)
    }
}
