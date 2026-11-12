import SwiftUI

/// Settings with the desktop's General, Appearance and Playback tabs, as grouped flat panels.
struct SettingsView: View {
    enum Tab: CaseIterable {
        case general, appearance, playback

        var title: LocalizedStringKey {
            switch self {
            case .general: "General"
            case .appearance: "Appearance"
            case .playback: "Playback"
            }
        }
    }

    @State private var tab: Tab = .general

    var body: some View {
        Page("Settings") {
            VStack(spacing: 0) {
                TabStrip(selection: $tab)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch tab {
                        case .general: GeneralSettings()
                        case .appearance: AppearanceSettings()
                        case .playback: PlaybackSettings()
                        }
                    }
                    .padding(.horizontal, Theme.inset)
                    .padding(.vertical, 16)
                }
            }
        }
    }
}

/// Underlined tab row under the page title, like the desktop settings tabs.
private struct TabStrip: View {
    @Binding var selection: SettingsView.Tab

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                ForEach(SettingsView.Tab.allCases, id: \.self) { tab in
                    Button { selection = tab } label: {
                        Text(tab.title)
                            .font(.bodyStrong)
                            .foregroundStyle(selection == tab ? Theme.foreground : Theme.mutedForeground)
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(selection == tab ? Theme.foreground : .clear)
                                    .frame(height: 2)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                }
                Spacer()
            }
            .padding(.horizontal, Theme.inset)
            Hairline()
        }
    }
}

// MARK: - Tabs

private struct GeneralSettings: View {
    @Environment(YouTubeSession.self) private var youtube
    @Environment(Toasts.self) private var toasts
    @State private var showsSignIn = false

    var body: some View {
        SettingsGroup("Providers") {
            youtubeRow
            ForEach(Array(providers.enumerated()), id: \.offset) { _, entry in
                RowDivider()
                HStack(spacing: 10) {
                    Icon(entry.icon, size: 16).foregroundStyle(Theme.mutedForeground)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name).font(.bodyText).foregroundStyle(Theme.foreground)
                        Text("Native client required").font(.small).foregroundStyle(Theme.mutedForeground)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 52)
            }
        }
        .sheet(isPresented: $showsSignIn) {
            YouTubeSignInView { header in
                do {
                    try youtube.signIn(cookies: header)
                    toasts.post(Toast(.done, String(localized: "Signed in to YouTube Music")))
                } catch {
                    toasts.post(Toast(.failed, String(localized: "YouTube Music sign-in failed")).detail(error.localizedDescription))
                }
            }
        }
        SettingsGroup("About") {
            SettingRow("Sonora for iPhone") { Text("0.1.0").foregroundStyle(Theme.mutedForeground) }
            RowDivider()
            Text("A native Swift rewrite. The desktop Rust runtime is not embedded in this app.")
                .font(.small)
                .foregroundStyle(Theme.mutedForeground)
                .padding(12)
        }
    }

    private var youtubeRow: some View {
        HStack(spacing: 10) {
            Icon("music", size: 16).foregroundStyle(Theme.mutedForeground)
            VStack(alignment: .leading, spacing: 2) {
                Text("YouTube Music").font(.bodyText).foregroundStyle(Theme.foreground)
                Text(youtube.isSignedIn ? "Signed in" : "Not signed in")
                    .font(.small)
                    .foregroundStyle(Theme.mutedForeground)
            }
            Spacer()
            Button(youtube.isSignedIn ? "Sign out" : "Sign in") {
                switch youtube.isSignedIn {
                case true: youtube.signOut()
                case false: showsSignIn = true
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
    }

    private let providers: [(name: LocalizedStringKey, icon: String)] = [
        ("Apple Music", "music"),
        ("Spotify", "music"),
        ("Deezer", "music"),
        ("Subsonic / Navidrome", "disc-3"),
    ]
}

private struct PlaybackSettings: View {
    var body: some View {
        SettingsGroup("Playback") {
            SettingRow("Audio engine") { Text("AVPlayer").foregroundStyle(Theme.mutedForeground) }
            RowDivider()
            SettingRow("Background audio") { Text("Enabled").foregroundStyle(Theme.mutedForeground) }
        }
    }
}

/// Every visual setting from the desktop Appearance tab that makes sense on a phone. Window
/// opacity, window blur, decorations, OS fullscreen and the lyrics and visualizer options are
/// left out because iPhone has no such windows, and no lyrics or spectrum yet.
private struct AppearanceSettings: View {
    var body: some View {
        @Bindable var look = Appearance.shared

        SettingsGroup("General") {
            SettingRow("Theme", detail: "Choose the application colour palette", stacked: true) {
                ThemeGrid()
            }
            RowDivider()
            SettingRow("Adaptive theme", detail: "Tint the palette with the artwork of the playing album") {
                Switch(isOn: $look.adaptive)
            }
            RowDivider()
            SettingRow("Icon pack", detail: "Choose the icon set the interface draws from") {
                MenuPicker(selection: $look.iconPack, options: IconPack.allCases) { Text($0.title) }
            }
            RowDivider()
            SettingRow("Blur UI", detail: "Frost the player and tab bar over whatever they cover") {
                Switch(isOn: $look.blur)
            }
            RowDivider()
            SettingRow("Corners", detail: "How rounded surfaces and controls are", stacked: true) {
                Segmented(selection: $look.corners, options: Rounding.allCases)
            }
        }

        SettingsGroup("Fullscreen") {
            SettingRow("Ambient background", detail: "Fill the full-screen player with colours drawn from the cover") {
                Switch(isOn: $look.ambient)
            }
            if look.ambient {
                RowDivider()
                SettingRow("Ambient motion", detail: "Drift the ambient colours instead of holding them still") {
                    Switch(isOn: $look.ambientMotion)
                }
            }
        }

        SettingsGroup("Text") {
            SettingRow("Font size", detail: "Base text size, everything else scales with it", stacked: true) {
                HStack(spacing: 12) {
                    Slider(value: $look.fontSize, in: Appearance.fontRange, step: 1)
                        .tint(Theme.primary)
                    Text("\(Int(look.fontSize)) px")
                        .font(.small.monospacedDigit())
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(minWidth: 40, alignment: .trailing)
                }
            }
            RowDivider()
            SettingRow("Font", detail: "The typeface Sonora uses across the interface") {
                MenuPicker(selection: $look.typeface, options: Typeface.allCases) { Text($0.title) }
            }
        }

        SettingsGroup("Motion") {
            SettingRow("Reduce motion", detail: "Skip interface animations and transitions") {
                Switch(isOn: $look.reduceMotion)
            }
            RowDivider()
            SettingRow("Animation speed", detail: "How fast interface animations play", stacked: true) {
                Segmented(selection: $look.pace, options: Pace.allCases)
            }
        }

        Button("Reset appearance") { Appearance.shared.reset() }
            .buttonStyle(SecondaryButtonStyle())
    }
}

// MARK: - Building blocks

/// A titled panel of rows, with the eyebrow label above it.
private struct SettingsGroup<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(title)
            VStack(spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.secondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .stroke(Theme.border, lineWidth: Theme.hairline)
                )
        }
    }
}

private struct RowDivider: View {
    var body: some View { Hairline().padding(.leading, 12) }
}

/// A setting: title and optional detail on the left, a control on the right. `stacked` drops the
/// control under the text for wide controls like sliders and swatch grids.
private struct SettingRow<Control: View>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    let stacked: Bool
    let control: Control

    init(
        _ title: LocalizedStringKey,
        detail: LocalizedStringKey? = nil,
        stacked: Bool = false,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.detail = detail
        self.stacked = stacked
        self.control = control()
    }

    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 12) {
                    text
                    control
                }
            } else {
                HStack(spacing: 12) {
                    text
                    Spacer(minLength: 8)
                    control
                }
            }
        }
        .font(.bodyText)
        .padding(12)
        .frame(minHeight: 44)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.bodyText).foregroundStyle(Theme.foreground)
            if let detail {
                Text(detail).font(.small).foregroundStyle(Theme.mutedForeground)
            }
        }
    }
}

/// Flat on/off switch in the primary color.
private struct Switch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(Appearance.shared.animation(0.15)) { isOn.toggle() }
        } label: {
            Capsule()
                .fill(isOn ? Theme.primary : Theme.muted)
                .frame(width: 40, height: 22)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? Theme.primaryForeground : Theme.mutedForeground)
                        .frame(width: 16, height: 16)
                        .padding(3)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// Dropdown showing the current choice. Opens a themed list in a popover, with a check beside the
/// chosen option, the desktop `Picker`.
private struct MenuPicker<Option: Hashable & Identifiable, Label: View>: View {
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> Label
    @State private var isOpen = false

    init(selection: Binding<Option>, options: [Option], @ViewBuilder label: @escaping (Option) -> Label) {
        _selection = selection
        self.options = options
        self.label = label
    }

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 8) {
                label(selection).font(.bodyStrong).foregroundStyle(Theme.foreground)
                Icon("chevron-down", size: 14)
                    .foregroundStyle(Theme.mutedForeground)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(isOpen ? Theme.hover : Theme.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .stroke(isOpen ? Theme.foreground.opacity(0.5) : Theme.border, lineWidth: Theme.hairline)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
            DropdownList(selection: $selection, options: options, label: label) { isOpen = false }
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// The option list inside a dropdown popover: flat rows, hover fill on press, a check on the chosen one.
private struct DropdownList<Option: Hashable & Identifiable, Label: View>: View {
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> Label
    let dismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(options) { option in
                    Button {
                        selection = option
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            label(option)
                                .font(.bodyText)
                                .foregroundStyle(Theme.foreground)
                            Spacer(minLength: 16)
                            if option == selection {
                                Icon("check", size: 14).foregroundStyle(Theme.foreground)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(DropdownRowStyle(isSelected: option == selection))
                    .accessibilityAddTraits(option == selection ? .isSelected : [])
                }
            }
            .padding(4)
        }
        .frame(minWidth: 180, maxHeight: 280)
        .fixedSize(horizontal: true, vertical: true)
        .background(Theme.popover)
        .presentationBackground(Theme.popover)
    }
}

/// Row fill for a dropdown option: highlighted while pressed or when it is the current choice.
private struct DropdownRowStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: max(Theme.radius - 2, 0), style: .continuous)
                    .fill(configuration.isPressed || isSelected ? Theme.hover : .clear)
            )
    }
}

/// Equal-width option strip with the chosen option filled.
private struct Segmented<Option: Hashable & Identifiable>: View where Option: Titled {
    @Binding var selection: Option
    let options: [Option]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                Button {
                    withAnimation(Appearance.shared.animation(0.15)) { selection = option }
                } label: {
                    Text(option.title)
                        .font(.label)
                        .foregroundStyle(selection == option ? Theme.primaryForeground : Theme.foreground)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                                .fill(selection == option ? Theme.primary : Theme.background)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                                .stroke(Theme.border, lineWidth: Theme.hairline)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
    }
}

/// An option that carries a localized title.
private protocol Titled {
    var title: LocalizedStringKey { get }
}

extension Rounding: Titled {}
extension Pace: Titled {}

/// Palette swatches: the palette's background with its primary and selection colors as dots.
private struct ThemeGrid: View {
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        let look = Appearance.shared
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(ThemeKind.allCases) { kind in
                let palette = kind.palette(systemIsDark: look.systemIsDark)
                Button { look.theme = kind } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Circle().fill(Color(UIColor(hex: palette.primary))).frame(width: 12, height: 12)
                            Circle().fill(Color(UIColor(hex: palette.selection))).frame(width: 12, height: 12)
                            Circle().fill(Color(UIColor(hex: palette.muted))).frame(width: 12, height: 12)
                        }
                        Text(kind.title)
                            .font(.label)
                            .foregroundStyle(Color(UIColor(hex: palette.foreground)))
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                            .fill(Color(UIColor(hex: palette.background)))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                            .stroke(look.theme == kind ? Theme.foreground : Theme.border,
                                    lineWidth: look.theme == kind ? 2 : Theme.hairline)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(look.theme == kind ? .isSelected : [])
            }
        }
    }
}
