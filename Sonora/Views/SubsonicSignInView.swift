import SwiftUI

/// Form sheet to sign in to a Subsonic or Navidrome server using OpenSubsonic salted token auth.
struct SubsonicSignInView: View {
    @Environment(SubsonicSession.self) private var subsonic
    @Environment(\.dismiss) private var dismiss

    let onSignedIn: () -> Void

    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Connect to any Subsonic or Navidrome server using your account credentials.")
                        .font(.small)
                        .foregroundStyle(Theme.mutedForeground)

                    VStack(spacing: 0) {
                        fieldRow("Server URL", prompt: "https://music.example.com", text: $server)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                        Hairline()
                        fieldRow("Username", prompt: "username", text: $username)
                            .textContentType(.username)
                        Hairline()
                        secureRow("Password", prompt: "password", text: $password)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.secondary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                            .stroke(Theme.border, lineWidth: Theme.hairline)
                    )

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.small)
                            .foregroundStyle(Theme.danger)
                    }

                    Button {
                        submit()
                    } label: {
                        HStack(spacing: 8) {
                            if isSubmitting {
                                ProgressView().tint(Theme.primaryForeground)
                            }
                            Text(isSubmitting ? "Connecting…" : "Sign in")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSubmit)
                }
                .padding(.horizontal, Theme.inset)
                .padding(.top, 16)
            }
            .background(Theme.background)
            .navigationTitle("Subsonic / Navidrome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
        }
    }

    private func fieldRow(_ title: LocalizedStringKey, prompt: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.small).foregroundStyle(Theme.mutedForeground)
            TextField("", text: text, prompt: Text(prompt).foregroundColor(Theme.mutedForeground))
                .font(.bodyText)
                .foregroundStyle(Theme.foreground)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(12)
    }

    private func secureRow(_ title: LocalizedStringKey, prompt: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.small).foregroundStyle(Theme.mutedForeground)
            SecureField("", text: text, prompt: Text(prompt).foregroundColor(Theme.mutedForeground))
                .font(.bodyText)
                .foregroundStyle(Theme.foreground)
                .textContentType(.password)
        }
        .padding(12)
    }

    private func submit() {
        errorMessage = nil
        isSubmitting = true
        Task { @MainActor in
            defer { isSubmitting = false }
            do {
                try await subsonic.signIn(server: server, username: username, password: password)
                onSignedIn()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
