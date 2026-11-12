import SwiftUI

/// The toasts above the player bar, newest in front. A toast dragged right far enough is closed,
/// and a finger on the stack stops every toast's clock.
struct ToastStack: View {
    @Environment(Toasts.self) private var toasts

    var body: some View {
        VStack(spacing: Self.gap) {
            ForEach(toasts.shown) { toast in
                ToastCard(toast: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, Theme.inset)
        .animation(Appearance.shared.animation(0.25), value: toasts.shown.map(\.id))
    }

    private static let gap: CGFloat = 10
}

/// One toast card: an optional icon or spinner, a message with an optional muted line under it,
/// an action button and a close button.
private struct ToastCard: View {
    @Environment(Toasts.self) private var toasts
    let toast: Toast
    @State private var offset: CGFloat = 0

    private static let iconSize: CGFloat = 16
    private static let fling: CGFloat = 45

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.message)
                    .font(.label)
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = toast.detail {
                    Text(detail)
                        .font(.small)
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let action = toast.action {
                Button(action.label) { toasts.press(toast.id) }
                    .buttonStyle(ToastActionStyle())
            }
            Button { toasts.close(toast.id) } label: {
                Icon("x", size: 14).foregroundStyle(Theme.mutedForeground)
            }
            .buttonStyle(GhostButtonStyle(size: 28))
            .accessibilityLabel("Dismiss")
        }
        .padding(Theme.inset * 0.6)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.popover)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(Theme.border, lineWidth: Theme.hairline)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        .offset(x: offset)
        .opacity(1 - min(offset, 120) / 240)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    toasts.pause(true)
                    offset = max(0, value.translation.width)
                }
                .onEnded { value in
                    toasts.pause(false)
                    switch value.translation.width >= Self.fling
                        || value.predictedEndTranslation.width > Self.fling * 3 {
                    case true: toasts.close(toast.id)
                    case false: withAnimation(Appearance.shared.animation(0.25)) { offset = 0 }
                    }
                }
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var leading: some View {
        switch toast.outcome {
        case .loading:
            ProgressView().tint(Theme.foreground).frame(width: Self.iconSize, height: Self.iconSize)
        default:
            if let icon = toast.outcome.icon {
                Icon(icon, size: Self.iconSize).foregroundStyle(Theme.foreground)
            }
        }
    }
}

/// The outlined button on a toast, the desktop `outline` small variant.
private struct ToastActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.label)
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 12)
            .frame(minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(configuration.isPressed ? Theme.hover : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .stroke(Theme.border, lineWidth: Theme.hairline)
            )
            .contentShape(Rectangle())
    }
}
