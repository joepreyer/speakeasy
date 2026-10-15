import Foundation

enum DictationPipeline {
    struct Output {
        let raw: String
        let text: String
    }

    /// Transcribes the audio, then (if enabled) formats it. Formatting failures fall back to the raw transcript.
    static func run(audio: URL, context: DictationContext, apiKey: String) async throws -> Output {
        let settings = Settings.shared
        let terms = AppStore.shared.terms.map(\.term)

        let raw = try await Transcriber.transcribe(
            fileURL: audio,
            apiKey: apiKey,
            model: settings.effectiveTranscriptionModel,
            vocabulary: terms,
            prompt: context.transcriptionPrompt
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !raw.isEmpty, settings.smartFormatting else { return Output(raw: raw, text: raw) }

        var files: [String] = []
        if settings.tagFiles, context.isDeveloperApp, let root = context.workspaceRoot {
            files = FileMatcher.candidates(in: raw, files: FileIndex.shared.files(in: root))
        }

        do {
            let text = try await Formatter.format(
                raw,
                context: context,
                terms: terms,
                files: files,
                apiKey: apiKey,
                model: settings.effectiveFormattingModel
            )
            return Output(raw: raw, text: text)
        } catch {
            NSLog("SpeakEasy: formatting failed, using raw transcript: \(error.localizedDescription)")
            return Output(raw: raw, text: raw)
        }
    }
}
