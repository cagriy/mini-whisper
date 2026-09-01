public enum EngineName: String, Codable, CaseIterable, Sendable {
    case speechAnalyzer = "speech_analyzer"
    case onDevice = "on_device"
    case openai
    case elevenlabs
    case speechmatics
}
