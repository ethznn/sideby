import SidebyCore
import SwiftUI

public struct LanguageSettingsView: View {
    @Binding private var settings: AppSettings

    public init(settings: Binding<AppSettings>) {
        self._settings = settings
    }

    public var body: some View {
        let strings = SBSStrings(language: settings.language)

        VStack(alignment: .leading, spacing: 8) {
            Text(strings.languageTitle)
                .font(.subheadline.weight(.semibold))

            Picker(strings.languageTitle, selection: Binding(
                get: { settings.language },
                set: { language in
                    var candidate = settings
                    candidate.language = language
                    settings = candidate
                }
            )) {
                ForEach(AppLanguage.allCases) { language in
                    Text(strings.languageName(language)).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)

            Text(strings.languageHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview("Language Settings") {
    @Previewable @State var settings = AppSettings.default
    LanguageSettingsView(settings: $settings)
        .padding()
}
#endif
