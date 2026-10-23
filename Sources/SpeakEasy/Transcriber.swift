import Foundation

enum OpenAIError: LocalizedError {
    case badResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .badResponse: return "Unexpected response from OpenAI"
        case .api(let message): return message
        }
    }
}

enum OpenAI {
    static func perform(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = (json?["error"] as? [String: Any])?["message"] as? String
            throw OpenAIError.api(message ?? "OpenAI error (HTTP \(http.statusCode))")
        }
        guard let json else { throw OpenAIError.badResponse }
        return json
    }

    /// Opens the HTTPS connection while the user is still talking, so the requests
    /// after release skip DNS, TCP, and TLS setup.
    static func warmUp(apiKey: String, model: String) {
        guard let url = URL(string: "https://api.openai.com/v1/models/\(model)") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request).resume()
    }

    static func validate(apiKey: String) async throws {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        _ = try await perform(request)
    }
}

enum Transcriber {
    private static let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    static func transcribe(fileURL: URL, apiKey: String, model: String,
                           vocabulary: [String], prompt: String?) async throws -> String {
        let audio = try Data(contentsOf: fileURL)
        let terms = vocabulary.map(sanitize).filter { !$0.isEmpty }

        var form = MultipartForm()
        form.addField("model", model)

        var promptText = prompt ?? ""
        if supportsKeywords(model) {
            for term in terms.prefix(200) { form.addField("keywords[]", term) }
        } else if !terms.isEmpty {
            // Older models only take vocabulary through the (length-limited) prompt.
            promptText += " Vocabulary: " + terms.prefix(40).joined(separator: ", ")
        }
        promptText = promptText.trimmingCharacters(in: .whitespaces)
        if !promptText.isEmpty { form.addField("prompt", promptText) }
        form.addFile("file", filename: "audio.m4a", contentType: "audio/mp4", data: audio)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finalized()

        let json = try await OpenAI.perform(request)
        guard let text = json["text"] as? String else { throw OpenAIError.badResponse }
        return text
    }

    private static func supportsKeywords(_ model: String) -> Bool {
        model.hasPrefix("gpt-transcribe")
    }

    /// Keywords may not contain angle brackets or line breaks; the API rejects the whole request otherwise.
    private static func sanitize(_ term: String) -> String {
        String(term.filter { $0 != "<" && $0 != ">" && !$0.isNewline })
            .trimmingCharacters(in: .whitespaces)
    }
}

struct MultipartForm {
    private let boundary = "speakeasy-\(UUID().uuidString)"
    private var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(_ name: String, _ value: String) {
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
    }

    mutating func addFile(_ name: String, filename: String, contentType: String, data: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    func finalized() -> Data {
        var result = body
        result.append(Data("--\(boundary)--\r\n".utf8))
        return result
    }

    private mutating func append(_ string: String) {
        body.append(Data(string.utf8))
    }
}
