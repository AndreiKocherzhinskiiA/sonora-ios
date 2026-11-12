import Foundation
import Observation

/// What a toast reports, which picks its icon. `loading` stays up until it is settled or closed.
enum ToastOutcome: Equatable {
    case plain
    case done
    case info
    case warning
    case failed
    case loading

    var icon: String? {
        switch self {
        case .plain, .loading: nil
        case .done: "circle-check"
        case .info: "info"
        case .warning: "triangle-alert"
        case .failed: "octagon-x"
        }
    }
}

/// One toast, built with the modifiers below and shown with `Toasts.post`.
struct Toast: Identifiable {
    var id = 0
    var outcome: ToastOutcome
    /// The message, already localised by the caller.
    var message: String
    /// A line of its own below the message, such as the error behind a failure.
    var detail: String?
    /// The emphasised button, such as Undo.
    var action: (label: String, run: () -> Void)?
    /// Runs when the toast goes away without its action being pressed, so a deferred change can
    /// be made final.
    var onExpire: (() -> Void)?
    /// How long the toast stays while nobody holds it, or `nil` to stay until closed.
    fileprivate(set) var linger: Duration?

    init(_ outcome: ToastOutcome, _ message: String) {
        self.outcome = outcome
        self.message = message
        self.linger = outcome == .loading ? nil : Toasts.linger
    }

    func detail(_ detail: String) -> Toast {
        var copy = self
        copy.detail = detail
        return copy
    }

    func action(_ label: String, _ run: @escaping () -> Void) -> Toast {
        var copy = self
        copy.action = (label, run)
        return copy
    }

    /// Adds an Undo button. `run` puts back what the toast reports was removed, and has to cope
    /// with everything that changed since, because the toast stays up for seconds.
    func undo(_ run: @escaping () -> Void) -> Toast {
        action(String(localized: "Undo"), run)
    }

    func onExpire(_ run: @escaping () -> Void) -> Toast {
        var copy = self
        copy.onExpire = run
        return copy
    }

    /// Keeps the toast up until the user or the code closes it.
    func lasting() -> Toast {
        var copy = self
        copy.linger = nil
        return copy
    }
}

/// The toasts on screen, oldest first. Every toast's clock stops while the stack is paused, which
/// it is while a finger is on it.
@MainActor
@Observable
final class Toasts {
    static let linger: Duration = .seconds(4)

    private(set) var shown: [Toast] = []

    @ObservationIgnored private var next = 1
    @ObservationIgnored private var paused = false
    @ObservationIgnored private var clocks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var started: [Int: ContinuousClock.Instant] = [:]
    @ObservationIgnored private var spent: [Int: Duration] = [:]

    /// Shows a toast and returns its id, which `settle` and `close` take. Every call shows a new
    /// toast, except a failure or warning that says the same thing as one already up. Those can
    /// fire again on their own, so the one up restarts its clock instead.
    @discardableResult
    func post(_ toast: Toast) -> Int {
        let repeats = toast.outcome == .failed || toast.outcome == .warning
        if repeats, let existing = shown.first(where: {
            $0.outcome == toast.outcome && $0.message == toast.message && $0.detail == toast.detail
        }) {
            arm(existing.id, restart: true)
            return existing.id
        }

        var toast = toast
        toast.id = next
        next += 1
        shown.append(toast)
        arm(toast.id, restart: true)
        return toast.id
    }

    /// Replaces what toast `id` says and restarts its clock, the way a loading toast turns into
    /// its result. Nothing happens when the toast is already gone.
    func settle(_ id: Int, with toast: Toast) {
        guard let at = shown.firstIndex(where: { $0.id == id }) else { return }
        var toast = toast
        toast.id = id
        shown[at] = toast
        arm(id, restart: true)
    }

    /// Closes toast `id` from outside the stack, running its expiry work.
    func close(_ id: Int) {
        finish(id, pressed: false)
    }

    /// Runs the action of toast `id`, then closes it.
    func press(_ id: Int) {
        finish(id, pressed: true)
    }

    /// Stops or restarts every toast's clock. A restarted clock runs only the time it had left.
    func pause(_ paused: Bool) {
        guard self.paused != paused else { return }
        self.paused = paused
        let now = ContinuousClock.now
        for toast in shown {
            switch paused {
            case true:
                spent[toast.id, default: .zero] += started[toast.id].map { now - $0 } ?? .zero
                clocks[toast.id]?.cancel()
                clocks[toast.id] = nil
            case false:
                arm(toast.id, restart: false)
            }
        }
    }

    private func finish(_ id: Int, pressed: Bool) {
        guard let at = shown.firstIndex(where: { $0.id == id }) else { return }
        let toast = shown.remove(at: at)
        clocks[id]?.cancel()
        clocks[id] = nil
        started[id] = nil
        spent[id] = nil
        switch pressed {
        case true: toast.action?.run()
        case false: toast.onExpire?()
        }
    }

    /// Starts the clock that closes toast `id` once the time it has left runs out. A paused stack
    /// and a toast that never expires get no clock.
    private func arm(_ id: Int, restart: Bool) {
        clocks[id]?.cancel()
        clocks[id] = nil
        if restart { spent[id] = .zero }
        started[id] = .now
        guard !paused,
              let toast = shown.first(where: { $0.id == id }),
              let linger = toast.linger else { return }
        let wait = max(.zero, linger - spent[id, default: .zero])
        clocks[id] = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.close(id)
        }
    }
}
