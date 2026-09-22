import Foundation

struct AppConfiguration: Equatable {
    let supabaseURL: URL
    let publishableKey: String

    static func load(bundle: Bundle = .main) throws -> AppConfiguration {
        guard let rawURL = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let url = URL(string: rawURL),
              url.scheme == "https",
              !rawURL.contains("YOUR_PROJECT_REF") else {
            throw ConfigurationError.missingURL
        }
        guard let key = bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String,
              !key.isEmpty,
              !key.contains("YOUR_PUBLISHABLE_KEY") else {
            throw ConfigurationError.missingPublishableKey
        }
        return AppConfiguration(supabaseURL: url, publishableKey: key)
    }
}

enum ConfigurationError: LocalizedError {
    case missingURL
    case missingPublishableKey

    var errorDescription: String? {
        switch self {
        case .missingURL:
            return "Set SUPABASE_URL in Config/Supabase.local.xcconfig."
        case .missingPublishableKey:
            return "Set SUPABASE_PUBLISHABLE_KEY in Config/Supabase.local.xcconfig."
        }
    }
}
