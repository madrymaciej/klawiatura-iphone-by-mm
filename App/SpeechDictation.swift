import AVFoundation
import Foundation
import Speech

/// Dyktowanie po polsku silnikiem rozpoznawania mowy iOS (Speech framework, pl-PL).
final class SpeechDictation: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "pl-PL"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Tekst z poprzednich fragmentów nagrania (rozpoznawanie można wznawiać).
    private var committedText = ""

    func start() {
        guard !isRecording else { return }
        errorMessage = nil
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self.errorMessage = "Brak zgody na rozpoznawanie mowy (Ustawienia › Klawiatura MM)."
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        if granted {
                            self.begin()
                        } else {
                            self.errorMessage = "Brak zgody na mikrofon (Ustawienia › Klawiatura MM)."
                        }
                    }
                }
            }
        }
    }

    private func begin() {
        guard !isRecording else { return }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Rozpoznawanie mowy po polsku jest teraz niedostępne."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            self.request = request

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
                request?.append(buffer)
            }
            engine.prepare()
            try engine.start()

            committedText = transcript.isEmpty ? "" : transcript + " "
            isRecording = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let result {
                        self.transcript = self.committedText + result.bestTranscription.formattedString
                    }
                    if error != nil || (result?.isFinal ?? false) {
                        self.stop()
                    }
                }
            }
        } catch {
            errorMessage = "Nie udało się uruchomić mikrofonu: \(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        request = nil
        task = nil
        if isRecording {
            isRecording = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func clear() {
        transcript = ""
        committedText = ""
    }
}
