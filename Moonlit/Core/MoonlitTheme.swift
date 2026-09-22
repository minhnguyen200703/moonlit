import SwiftUI

enum MoonlitTheme {
    static let burgundy = Color(red: 88 / 255, green: 28 / 255, blue: 50 / 255)
    static let wine = Color(red: 123 / 255, green: 41 / 255, blue: 69 / 255)
    static let blush = Color(red: 233 / 255, green: 185 / 255, blue: 198 / 255)
    static let cream = Color(red: 1, green: 244 / 255, blue: 231 / 255)
    static let moonGold = Color(red: 230 / 255, green: 198 / 255, blue: 139 / 255)
    static let softSurface = Color(red: 248 / 255, green: 232 / 255, blue: 228 / 255)
}
struct MoonMark: View {
    var size: CGFloat = 72

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(MoonlitTheme.moonGold)
            Circle()
                .fill(MoonlitTheme.burgundy)
                .frame(width: size * 0.78, height: size * 0.78)
                .offset(x: size * 0.12, y: -size * 0.03)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Crescent moon")
    }
}
