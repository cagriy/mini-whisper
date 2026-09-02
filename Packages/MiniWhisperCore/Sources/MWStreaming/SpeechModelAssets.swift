import Foundation

/// Availability and installation of the on-device speech model (F24, F32).
public enum SpeechModelAssets {
    public static func status(api: any SpeechAnalyzerAPI, locale: Locale = .current) async -> AssetStatus {
        guard let supported = await supportedLocale(api: api, locale: locale) else { return .unavailable }
        if await api.isInstalled(locale: supported) { return .installed }
        do {
            guard let request = try await api.installationRequest(for: supported) else { return .installed }
            let fraction = request.fractionCompleted
            guard fraction > 0, fraction < 1 else { return .notInstalled }
            return .installing(fractionCompleted: fraction)
        } catch {
            return .unavailable
        }
    }

    /// Downloads the assets the transcriber needs; a no-op once they are installed.
    public static func install(api: any SpeechAnalyzerAPI, locale: Locale = .current) async throws {
        guard let supported = await supportedLocale(api: api, locale: locale) else {
            throw SpeechAnalyzerError.unavailable
        }
        guard let request = try await api.installationRequest(for: supported) else { return }
        try await request.downloadAndInstall()
    }

    private static func supportedLocale(api: any SpeechAnalyzerAPI, locale: Locale) async -> Locale? {
        guard api.isAvailable else { return nil }
        return await api.supportedLocale(equivalentTo: locale)
    }
}
