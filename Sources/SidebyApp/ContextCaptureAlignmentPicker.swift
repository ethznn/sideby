import SwiftUI
import SidebyUI

struct ContextCaptureAlignmentPickerPresentation: Equatable {
    let title: String
    let message: String
    let optionLabels: [String]

    init(request: ProductContextCaptureAlignmentRequest, strings: SBSStrings) {
        title = strings.contextCaptureAlignmentTitle
        message = strings.contextCaptureAlignmentMessage
        optionLabels = request.candidates.map {
            strings.contextCaptureAlignmentOption(order: $0.order, name: $0.name)
        }
    }
}

struct ContextCaptureAlignmentPicker: View {
    let request: ProductContextCaptureAlignmentRequest
    let presentation: ContextCaptureAlignmentPickerPresentation
    let strings: SBSStrings
    let choose: (String) -> Void
    let cancel: () -> Void

    init(
        request: ProductContextCaptureAlignmentRequest,
        strings: SBSStrings,
        choose: @escaping (String) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.request = request
        self.presentation = ContextCaptureAlignmentPickerPresentation(request: request, strings: strings)
        self.strings = strings
        self.choose = choose
        self.cancel = cancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(presentation.title)
                .font(.headline)

            Text(presentation.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(request.candidates.enumerated()), id: \.element.id) { index, candidate in
                    Button(presentation.optionLabels[index]) {
                        choose(candidate.id)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack {
                Spacer()
                Button(strings.cancel, action: cancel)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
        .padding()
    }
}
