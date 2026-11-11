import SwiftUI
import UIKit

struct DictationView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var speech = SpeechDictation()
    @State private var didSend = false
    @State private var handledRequest = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextEditor(text: $speech.transcript)
                    .frame(minHeight: 160)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if let error = speech.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    didSend = false
                    if speech.isRecording { speech.stop() } else { speech.start() }
                } label: {
                    Label(speech.isRecording ? "Zatrzymaj" : "Dyktuj po polsku",
                          systemImage: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(speech.isRecording ? .red : .accentColor)

                HStack {
                    Button("Wstaw do klawiatury") { send() }
                        .buttonStyle(.bordered)
                        .disabled(speech.transcript.isEmpty)
                    Button("Kopiuj") { UIPasteboard.general.string = speech.transcript }
                        .buttonStyle(.bordered)
                        .disabled(speech.transcript.isEmpty)
                    Button("Wyczyść") {
                        speech.clear()
                        didSend = false
                    }
                    .buttonStyle(.bordered)
                    .disabled(speech.transcript.isEmpty)
                }

                if didSend {
                    Label("Gotowe. Wróć do poprzedniej aplikacji (strzałka ‹ w lewym górnym rogu ekranu) — klawiatura sama wstawi tekst.",
                          systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Dyktowanie")
            .onChange(of: model.dictationRequest) { _, _ in
                startFromKeyboardRequest()
            }
            .onAppear {
                startFromKeyboardRequest()
            }
        }
    }

    /// Wywołanie z klawisza mikrofonu na klawiaturze (każde żądanie obsługujemy raz).
    private func startFromKeyboardRequest() {
        guard model.dictationRequest != handledRequest else { return }
        handledRequest = model.dictationRequest
        speech.stop()
        speech.clear()
        didSend = false
        speech.start()
    }

    private func send() {
        speech.stop()
        SharedSettings.pendingDictation = speech.transcript
        didSend = true
    }
}
