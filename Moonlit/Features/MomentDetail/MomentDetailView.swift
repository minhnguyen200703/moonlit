import SwiftUI

struct MomentDetailView: View {
    @EnvironmentObject private var store: MomentStore
    let moment: Moment
    @State private var replies: [Reply] = []
    @State private var draft = ""
    @State private var draftID = UUID()
    @State private var attemptedBody: String?
    @State private var isSending = false
    @State private var errorMessage: String?

    private var displayedMoment: Moment {
        store.moments.first(where: { $0.id == moment.id }) ?? moment
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MomentImageView(moment: displayedMoment, height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                if !displayedMoment.note.isEmpty {
                    Text(displayedMoment.note)
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(MoonlitTheme.burgundy)
                }
                Text("\(displayedMoment.createdByCurrentUser ? "You" : "Your person") · \(displayedMoment.capturedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(MoonlitTheme.wine)

                if displayedMoment.deliveryState == .failed {
                    Button("Retry sending this moment") {
                        Task { await store.retry(moment: displayedMoment) }
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    Task { await store.react(to: moment.id) }
                } label: {
                    Label(
                        displayedMoment.currentUserReacted == true ? "Remove your reaction" : "React with a heart",
                        systemImage: displayedMoment.currentUserReacted == true ? "heart.fill" : "heart"
                    )
                }
                .disabled(displayedMoment.deliveryState != .synced)

                Divider()
                Text("Replies").font(.headline).foregroundStyle(MoonlitTheme.burgundy)
                if replies.isEmpty {
                    Text("Leave a little note beneath this moment.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(replies) { reply in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(reply.createdByCurrentUser ? "You" : "Your person").font(.caption.bold())
                        Text(reply.body)
                        Text(reply.createdAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(reply.createdByCurrentUser ? MoonlitTheme.softSurface : .white.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
                }

                HStack(alignment: .bottom) {
                    TextField("Reply…", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(10)
                        .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                    Button {
                        Task { await send() }
                    } label: {
                        if isSending { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    }
                    .disabled(
                        isSending
                            || displayedMoment.deliveryState != .synced
                            || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
            .padding()
        }
        .background(MoonlitTheme.cream.ignoresSafeArea())
        .navigationTitle("Moment")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: store.syncRevision) { await reload() }
        .refreshable { await reload() }
        .alert("Could not send reply", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "Please try again.") }
    }

    private func reload() async {
        do { replies = try await store.replies(for: moment.id) }
        catch { errorMessage = error.localizedDescription }
    }

    private func send() async {
        let body = draft
        if let attemptedBody, attemptedBody != body { draftID = UUID() }
        attemptedBody = body
        isSending = true
        defer { isSending = false }
        do {
            try await store.sendReply(id: draftID, to: moment.id, body: body)
            draft = ""
            draftID = UUID()
            attemptedBody = nil
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
