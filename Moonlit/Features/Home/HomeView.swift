import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: MomentStore
    @Binding var openCameraRequest: Bool
    @State private var isCapturing = false
    private let phase = MoonPhase.current()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                latestMomentCard
                moonCard
                captureButton
            }
            .padding()
        }
        .background(MoonlitTheme.cream.ignoresSafeArea())
        .navigationBarHidden(true)
        .refreshable { await store.refreshMoments() }
        .fullScreenCover(isPresented: $isCapturing) { CaptureFlowView() }
        .onAppear {
            if openCameraRequest {
                isCapturing = true
                openCameraRequest = false
            }
        }
        .onChange(of: openCameraRequest) { _, requested in
            guard requested else { return }
            isCapturing = true
            openCameraRequest = false
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("OUR LITTLE UNIVERSE")
                    .font(.caption2.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(MoonlitTheme.wine)
                Text("Under the same moon ♡")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(MoonlitTheme.burgundy)
            }
            Spacer()
            if store.isSyncing { ProgressView().padding(.trailing, 6) }
            MoonMark(size: 48)
        }
    }

    @ViewBuilder
    private var latestMomentCard: some View {
        if let moment = store.latestMoment {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink {
                    MomentDetailView(moment: moment)
                } label: {
                    MomentImageView(moment: moment, height: 330)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                }
                .buttonStyle(.plain)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(moment.createdByCurrentUser ? "A moment from you ♡" : "A moment from your person ♡")
                            .fontWeight(.semibold)
                        if !moment.note.isEmpty { Text(moment.note).foregroundStyle(MoonlitTheme.blush) }
                        Text(moment.capturedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(MoonlitTheme.blush.opacity(0.85))
                        deliveryLabel(moment)
                    }
                    Spacer()
                    Button {
                        Task { await store.react(to: moment.id) }
                    } label: {
                        HStack(spacing: 3) {
                            Text(moment.currentUserReacted == true ? "♥︎" : (moment.reaction ?? "♡"))
                            if let count = moment.reactionCount, count > 0 {
                                Text("\(count)").font(.caption.bold())
                            }
                        }
                        .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .disabled(moment.deliveryState != .synced)
                }
                if moment.deliveryState == .synced {
                    NavigationLink {
                        MomentDetailView(moment: moment)
                    } label: {
                        Label("View replies", systemImage: "bubble.left.fill")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .foregroundStyle(MoonlitTheme.cream)
            .background(MoonlitTheme.burgundy, in: RoundedRectangle(cornerRadius: 26))
        } else {
            VStack(spacing: 14) {
                Image(systemName: "camera.fill").font(.largeTitle).foregroundStyle(MoonlitTheme.moonGold)
                Text("Your first moment belongs here").font(.system(.headline, design: .serif))
                Text("Take a photo and add a Moon Note.").font(.subheadline).foregroundStyle(MoonlitTheme.blush)
            }
            .frame(maxWidth: .infinity, minHeight: 260)
            .foregroundStyle(MoonlitTheme.cream)
            .background(MoonlitTheme.burgundy, in: RoundedRectangle(cornerRadius: 26))
        }
    }

    @ViewBuilder
    private func deliveryLabel(_ moment: Moment) -> some View {
        switch moment.deliveryState {
        case .queued, .uploading:
            Label("Sending…", systemImage: "arrow.triangle.2.circlepath").font(.caption2)
        case .failed:
            Button("Retry sending") { Task { await store.retry(moment: moment) } }
                .font(.caption2.bold())
        case .synced:
            EmptyView()
        }
    }

    private var moonCard: some View {
        HStack(spacing: 14) {
            Image(systemName: phase.symbol).font(.system(size: 38)).foregroundStyle(MoonlitTheme.moonGold)
            VStack(alignment: .leading, spacing: 3) {
                Text("Our moon tonight").font(.headline).foregroundStyle(MoonlitTheme.burgundy)
                Text("\(phase.name), \(phase.illumination)% illuminated").font(.caption).foregroundStyle(MoonlitTheme.wine)
                Text("Same moon, different skies ♡").font(.subheadline).foregroundStyle(MoonlitTheme.wine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(MoonlitTheme.softSurface, in: RoundedRectangle(cornerRadius: 20))
    }

    private var captureButton: some View {
        Button { isCapturing = true } label: {
            Label("Send a moment ♡", systemImage: "camera.fill")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(MoonlitTheme.cream)
                .background(MoonlitTheme.burgundy, in: Capsule())
        }
    }
}
