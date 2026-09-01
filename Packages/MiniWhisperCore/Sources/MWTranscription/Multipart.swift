import Foundation

/// Minimal `multipart/form-data` body builder for the transcription request
/// (design §5.4): parts are appended in call order.
struct Multipart {
    private let boundary: String
    private var body = Data()

    init(boundary: String = UUID().uuidString) {
        self.boundary = boundary
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addFile(name: String, filename: String, contentType: String, data: Data) {
        appendHeader("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
            + "Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    mutating func addField(name: String, value: String) {
        appendHeader("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    func finished() -> Data {
        body + Data("--\(boundary)--\r\n".utf8)
    }

    private mutating func appendHeader(_ header: String) {
        append("--\(boundary)\r\n" + header)
    }

    private mutating func append(_ text: String) {
        body.append(Data(text.utf8))
    }
}
