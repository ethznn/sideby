public enum ContextEditPolicy: Sendable {
    public static func minimumContextCount(
        selectedDisplayIDs: Set<String>,
        displays: [InstantCaptureDisplay]
    ) -> Int? {
        guard !selectedDisplayIDs.isEmpty else {
            return nil
        }

        let displaysByID = Dictionary(grouping: displays, by: \.displayID)
        var counts: [Int] = []
        for displayID in selectedDisplayIDs {
            guard let matches = displaysByID[displayID],
                  matches.count == 1,
                  let display = matches.first,
                  display.spaceCount >= 1
            else {
                return nil
            }
            counts.append(display.spaceCount)
        }
        return counts.min()
    }

    public static func canDelete(
        contextCount: Int,
        minimumContextCount: Int?
    ) -> Bool {
        guard contextCount >= 1,
              let minimumContextCount,
              minimumContextCount >= 1
        else {
            return false
        }
        return contextCount > minimumContextCount
    }

    public static func requiresDeleteConfirmation(
        for context: ContextDefinition
    ) -> Bool {
        !context.displaySpaceIndexes.isEmpty
    }
}
