import SwiftUI

struct CaptureFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: MomentStore
    @State private var capturedImage: UIImage?
    @State private var note = ""
    @State private var isShowingCamera = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                MoonlitTheme.cream.ignoresSafeArea()
                if let image = capturedImage {
                    preview(image)
                } else {
                    VStack(spacing: 14) {
                        MoonMark(size: 88)
                        Text("Capture a little piece of your world")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(MoonlitTheme.burgundy)
                        Button("Open camera") { isShowingCamera = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $isShowingCamera) {
            CameraPicker { capturedImage = $0 }
                .ignoresSafeArea()
        }
        .alert("Could not save moment", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "Please try again.") }
    }

    private func preview(_ image: UIImage) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: MoonlitTheme.burgundy.opacity(0.16), radius: 14, y: 7)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Moon Note", systemImage: "moon.stars")
                        .font(.headline)
                        .foregroundStyle(MoonlitTheme.burgundy)
                    TextField("saw this and thought of u ♡", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(12)
                        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
                }

                HStack(spacing: 12) {
                    Button("Retake") {
                        capturedImage = nil
                        isShowingCamera = true
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)

                    Button {
                        Task {
                            isSaving = true
                            defer { isSaving = false }
                            do {
                                try await store.add(image: image, note: note)
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Keep moment ♡") }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                }
            }
            .padding()
        }
    }
}
