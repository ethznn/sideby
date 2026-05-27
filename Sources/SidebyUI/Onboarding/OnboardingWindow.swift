import AppKit
import SwiftUI

@MainActor
public final class OnboardingWindowController<ViewModel: SBSOnboardingViewModel>: NSWindowController {
    private let hostingController: NSHostingController<OnboardingFlowView<ViewModel>>

    public init(viewModel: ViewModel) {
        let rootView = OnboardingFlowView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Sideby"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.center()

        self.hostingController = hostingController

        super.init(window: window)

        hostingController.rootView = OnboardingFlowView(viewModel: viewModel) { [weak self] in
            self?.close()
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func showOnboardingWindow() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
