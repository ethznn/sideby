public struct ContextSwitchResult: Equatable, Sendable {
    public let command: SwitchCommand
    public let didExecute: Bool
    public let diagnostics: [DiagnosticState]

    public init(command: SwitchCommand, didExecute: Bool, diagnostics: [DiagnosticState]) {
        self.command = command
        self.didExecute = didExecute
        self.diagnostics = diagnostics
    }
}

public struct ContextSwitchEngine<Executor: SpaceCommandExecuting>: Sendable {
    private let modePolicy: ModePolicy
    private let executor: Executor

    public init(modePolicy: ModePolicy = ModePolicy(), executor: Executor) {
        self.modePolicy = modePolicy
        self.executor = executor
    }

    public func switchContext(
        _ command: SwitchCommand,
        mode: AppMode,
        inputMethod: InputMethod,
        runtimeState: RuntimeState
    ) -> ContextSwitchResult {
        let decision = modePolicy.decision(
            for: mode,
            inputMethod: inputMethod,
            runtimeState: runtimeState
        )
        let diagnostics = DiagnosticRule.evaluate(decision: decision)

        guard decision.isAllowed else {
            return ContextSwitchResult(command: command, didExecute: false, diagnostics: diagnostics)
        }

        return ContextSwitchResult(
            command: command,
            didExecute: executor.execute(command),
            diagnostics: diagnostics
        )
    }
}
