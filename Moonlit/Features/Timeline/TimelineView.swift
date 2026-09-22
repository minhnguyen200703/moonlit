import SwiftUI

struct TimelineView: View {
    @EnvironmentObject private var store: MomentStore
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView {
            if store.moments.isEmpty {
                ContentUnavailableView(
                    "Your sky is waiting",
                    systemImage: "sparkles",
                    description: Text("Each shared photo becomes a star in your sky.")
                )
                .padding(.top, 90)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(store.moments) { moment in
                        NavigationLink {
                            MomentDetailView(moment: moment)
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                MomentImageView(moment: moment, height: 220)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                                LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                                VStack(alignment: .leading, spacing: 2) {
                                    if !moment.note.isEmpty { Text(moment.note).lineLimit(2) }
                                    Text(moment.capturedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                    if moment.deliveryState == .failed {
                                        Label("Tap to retry from Home", systemImage: "exclamationmark.circle")
                                            .font(.caption2)
                                    }
                                }
                                .foregroundStyle(.white)
                                .padding(10)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .refreshable { await store.refreshMoments() }
        .background(MoonlitTheme.cream.ignoresSafeArea())
        .navigationTitle("Our sky")
    }
}
