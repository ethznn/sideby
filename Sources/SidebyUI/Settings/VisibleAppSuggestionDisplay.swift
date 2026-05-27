import SidebyCore

public enum VisibleAppSuggestionDisplay {
    public static func detectedText(
        for suggestion: VisibleAppSuggestion,
        strings: SBSStrings
    ) -> String {
        strings.detectedApp(suggestion.combinedLabel)
    }
}
