import AVFoundation

enum RecorderError: LocalizedError {
    case cannotStart

    var errorDescription: String? { "Couldn't start the microphone" }
}

final class Recorder {
    private var recorder: AVAudioRecorder?
    private var startedAt: Date?

    var isRecording: Bool { recorder != nil }
    var duration: TimeInterval { startedAt.map { Date().timeIntervalSince($0) } ?? 0 }

    /// Current input loudness from 0 (silence) to 1.
    var level: Double {
        guard let recorder else { return 0 }
        recorder.updateMeters()
        let decibels = Double(recorder.averagePower(forChannel: 0))
        let normalized = max(0, min(1, (decibels + 50) / 45))
        return pow(normalized, 1.6)
    }

    func start() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("speakeasy-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        guard recorder.record() else { throw RecorderError.cannotStart }
        self.recorder = recorder
        startedAt = Date()
    }

    /// Stops recording and returns the audio file URL.
    func stop() -> URL? {
        guard let recorder else { return nil }
        recorder.stop()
        self.recorder = nil
        startedAt = nil
        return recorder.url
    }

    func cancel() {
        guard let recorder else { return }
        recorder.stop()
        recorder.deleteRecording()
        self.recorder = nil
        startedAt = nil
    }
}
