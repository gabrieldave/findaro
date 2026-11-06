import Foundation
import AVFoundation
import Speech
import AppKit

/// Push-to-talk local con Speech framework (no graba en continuo).
@MainActor
final class VoiceCaptureController: ObservableObject {
    static let shared = VoiceCaptureController()

    enum Phase: Equatable {
        case idle
        case requestingPermission
        case listening
        case processing
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript: String = ""

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-MX"))
        ?? SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
        ?? SFSpeechRecognizer()

    var isListening: Bool { if case .listening = phase { return true }; return false }

    func beginPushToTalk() {
        transcript = ""
        phase = .requestingPermission
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                guard status == .authorized else {
                    self.phase = .error("Permiso de reconocimiento de voz denegado")
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    Task { @MainActor in
                        guard granted else {
                            self.phase = .error("Permiso de micrófono denegado")
                            return
                        }
                        self.startEngine()
                    }
                }
            }
        }
    }

    func endPushToTalk() {
        guard isListening || phase == .processing else {
            stopEngine()
            return
        }
        phase = .processing
        recognitionRequest?.endAudio()
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        // La task entregará el texto final; timeout suave.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            if case .processing = self.phase {
                self.phase = .idle
                self.stopEngine()
            }
        }
    }

    func cancel() {
        stopEngine()
        transcript = ""
        phase = .idle
    }

    private func startEngine() {
        stopEngine()
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            phase = .error("Reconocimiento de voz no disponible offline en este Mac")
            return
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            phase = .error(error.localizedDescription)
            return
        }

        audioEngine = engine
        recognitionRequest = request
        phase = .listening

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.phase = .idle
                        self.stopEngine()
                    }
                }
                if let error {
                    if self.transcript.isEmpty {
                        self.phase = .error(error.localizedDescription)
                    } else {
                        self.phase = .idle
                    }
                    self.stopEngine()
                }
            }
        }
    }

    private func stopEngine() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
    }
}
