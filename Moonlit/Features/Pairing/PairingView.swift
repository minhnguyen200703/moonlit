import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var store: MomentStore
    @AppStorage("moonlitDisplayName") private var displayName = ""
    @State private var code = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    MoonMark(size: 92)
                    VStack(spacing: 6) {
                        Text(store.couple == nil ? "Make a private space for two" : "Waiting under the same moon")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                            .multilineTextAlignment(.center)
                        Text("Moonlit signs you in privately on this device. Pair once with a single-use invitation code.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(MoonlitTheme.wine)
                    }

                    TextField("Your name", text: $displayName)
                        .textInputAutocapitalization(.words)
                        .padding(13)
                        .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))

                    if let invitation = store.invitation {
                        VStack(spacing: 10) {
                            Text("Share this code")
                                .font(.headline)
                            Text(invitation.code)
                                .font(.system(.title, design: .monospaced, weight: .bold))
                                .textSelection(.enabled)
                            Text("Expires \(invitation.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(MoonlitTheme.wine)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(MoonlitTheme.softSurface, in: RoundedRectangle(cornerRadius: 18))
                    }

                    if store.couple == nil {
                        Button("Create an invitation") {
                            Task { await store.createInvitation(displayName: displayName) }
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .disabled(store.isPairing)

                        HStack { Rectangle().frame(height: 1); Text("or"); Rectangle().frame(height: 1) }
                            .foregroundStyle(MoonlitTheme.blush)

                        TextField("ABCD-EFGH-JKLM", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                            .padding(13)
                            .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
                        Button("Join with a code") {
                            Task { await store.join(code: code, displayName: displayName) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.isPairing)
                    } else {
                        Button(store.invitation == nil ? "Generate a new code" : "Replace this code") {
                            Task { await store.createInvitation(displayName: displayName) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.isPairing)
                        Text("Keep this screen open or return later. Moonlit will enter your shared sky when your person joins.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(MoonlitTheme.wine)
                    }

                    if store.isPairing { ProgressView() }

                    Text("Anonymous access belongs to this installation. Do not sign out or delete the app until account recovery is added.")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .background(MoonlitTheme.cream.ignoresSafeArea())
            .navigationTitle("Pair Moonlit")
            .task {
                while !Task.isCancelled && store.appState == .pairing {
                    try? await Task.sleep(for: .seconds(5))
                    await store.checkPairing()
                }
            }
        }
    }
}
