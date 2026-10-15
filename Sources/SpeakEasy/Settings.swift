import Foundation

enum DeveloperMode: String, CaseIterable, Identifiable {
    case auto, always, off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Automatic (code editors & terminals)"
        case .always: return "Always on"
        case .off: return "Off"
        }
    }
}

final class Settings: ObservableObject {
    static let shared = Settings()

    static let defaultTranscriptionModel = "gpt-transcribe"
    static let defaultFormattingModel = "gpt-6-luna"

    private let defaults = UserDefaults.standard

    @Published var transcriptionModel: String {
        didSet { defaults.set(transcriptionModel, forKey: "transcriptionModel") }
    }
    @Published var smartFormatting: Bool {
        didSet { defaults.set(smartFormatting, forKey: "smartFormatting") }
    }
    @Published var formattingModel: String {
        didSet { defaults.set(formattingModel, forKey: "formattingModel") }
    }
    @Published var developerMode: DeveloperMode {
        didSet { defaults.set(developerMode.rawValue, forKey: "developerMode") }
    }
    @Published var tagFiles: Bool {
        didSet { defaults.set(tagFiles, forKey: "tagFiles") }
    }
    @Published var learnCorrections: Bool {
        didSet { defaults.set(learnCorrections, forKey: "learnCorrections") }
    }

    var effectiveTranscriptionModel: String {
        let model = transcriptionModel.trimmingCharacters(in: .whitespaces)
        return model.isEmpty ? Self.defaultTranscriptionModel : model
    }

    var effectiveFormattingModel: String {
        let model = formattingModel.trimmingCharacters(in: .whitespaces)
        return model.isEmpty ? Self.defaultFormattingModel : model
    }

    private init() {
        transcriptionModel = defaults.string(forKey: "transcriptionModel") ?? Self.defaultTranscriptionModel
        smartFormatting = defaults.object(forKey: "smartFormatting") as? Bool ?? true
        formattingModel = defaults.string(forKey: "formattingModel") ?? Self.defaultFormattingModel
        developerMode = DeveloperMode(rawValue: defaults.string(forKey: "developerMode") ?? "") ?? .auto
        tagFiles = defaults.object(forKey: "tagFiles") as? Bool ?? true
        learnCorrections = defaults.object(forKey: "learnCorrections") as? Bool ?? true
    }
}
