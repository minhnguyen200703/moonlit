import SwiftUI

struct MomentImageView: View {
    @EnvironmentObject private var store: MomentStore
    let moment: Moment
    let height: CGFloat
    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if didFail {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                    Text("Photo unavailable").font(.caption)
                    Button("Retry") { Task { await load() } }.font(.caption)
                }
                .foregroundStyle(MoonlitTheme.wine)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MoonlitTheme.softSurface)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MoonlitTheme.softSurface)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .task(id: moment.id) { await load() }
    }

    private func load() async {
        didFail = false
        image = await store.image(for: moment)
        didFail = image == nil
    }
}
