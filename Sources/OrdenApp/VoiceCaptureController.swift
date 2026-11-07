import Foundation
import AVFoundation
import Speech
import AppKit

/// Push-to-talk local con Speech (solo mientras mantienes el botón).
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

    /// Se llama al soltar el botón con el texto final (si hubo).
    var onFinished: ((String) -> Void)?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var finishTask: Task<Void, Never>?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-MX"))
        ?? SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
        ?? SFSpeechRecognizer()

    var isListening: Bool {
        if case .listening = phase { return true }
        return false
    }

    var statusLabel: String {
        switch phase {
        case .idle: return "Mantén para hablar"
        case .requestingPermission: return "Pidiendo permiso…"
        case .listening: return transcript.isEmpty ? "Escuchando…" : transcript
        case .processing: return "Procesando…"
        case .error(let msg): return msg
        }
    }

    func beginPushToTalk() {
        finishTask?.cancel()
        transcript = ""
        phase = .requestingPermission

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                guard status == .authorized else {
                    self.phase = .error("Activa Reconocimiento de voz en Ajustes del sistema")
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    Task { @MainActor in
                        guard granted else {
                            self.phase = .error("Activa el micrófono para Ordena en Ajustes del sistema")
                            return
                        }
                        self.startEngine()
                    }
                }
            }
        }
    }

    func endPushToTalk() {
        guard phase == .listening || phase == .requestingPermission || phase == .processing else {
            return
        }
        if phase == .requestingPermission {
            cancel()
            return
        }
        phase = .processing
        recognitionRequest?.endAudio()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()

        finishTask?.cancel()
        finishTask = Task { @MainActor in
            // Espera resultado final; si no llega, usa el parcial.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            let text = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            self.stopEngine()
            self.phase = .idle
            if !text.isEmpty {
                self.onFinished?(text)
            }
        }
    }

    func cancel() {
        finishTask?.cancel()
        finishTask = nil
        stopEngine()
        transcript = ""
        phase = .idle
    }

    private func startEngine() {
        stopEngine()
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            phase = .error("Reconocimiento de voz no disponible en este Mac")
            return
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Preferir on-device; si el locale no lo soporta, Speech falla y avisamos.
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            phase = .error("No hay micrófono disponible")
            return
        }
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
                    if result.isFinal, case .processing = self.phase {
                        self.finishTask?.cancel()
                        let text = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.stopEngine()
                        self.phase = .idle
                        if !text.isEmpty {
                            self.onFinished?(text)
                        }
                    }
                }
                if let error {
                    // Cancelación al soltar no es error fatal si ya hay texto.
                    let ns = error as NSError
                    if ns.domain == "kAFAssistantErrorDomain", ns.code == 1110 {
                        return
                    }
                    if self.transcript.isEmpty, case .listening = self.phase {
                        self.phase = .error(error.localizedDescription)
                        self.stopEngine()
                    }
                }
            }
        }
    }

    private func stopEngine() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
    }
}
