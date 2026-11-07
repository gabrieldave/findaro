import Foundation
import AVFoundation
import Speech
import AppKit

/// Push-to-talk local con Speech (solo mientras mantienes el botón).
/// Los callbacks de Speech/TCC/AVFoundation llegan fuera del main thread → siempre saltamos al main.
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

        // Callback de TCC NO es MainActor — no tocar self aquí.
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                VoiceCaptureController.shared.didReceiveSpeechAuthorization(status)
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
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            finishWithCurrentTranscript()
        }
    }

    func cancel() {
        finishTask?.cancel()
        finishTask = nil
        stopEngine()
        transcript = ""
        phase = .idle
    }

    // MARK: - Auth hops (siempre en main)

    private func didReceiveSpeechAuthorization(_ status: SFSpeechRecognizerAuthorizationStatus) {
        guard status == .authorized else {
            phase = .error("Activa Reconocimiento de voz en Ajustes del sistema")
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                VoiceCaptureController.shared.didReceiveMicrophoneAccess(granted)
            }
        }
    }

    private func didReceiveMicrophoneAccess(_ granted: Bool) {
        guard granted else {
            phase = .error("Activa el micrófono para Ordena en Ajustes del sistema")
            return
        }
        startEngine()
    }

    // MARK: - Engine

    private func startEngine() {
        stopEngine()
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            phase = .error("Reconocimiento de voz no disponible en este Mac")
            return
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
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

        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            DispatchQueue.main.async {
                VoiceCaptureController.shared.didReceiveRecognition(result: result, error: error)
            }
        }
    }

    private func didReceiveRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            transcript = result.bestTranscription.formattedString
            if result.isFinal, case .processing = phase {
                finishTask?.cancel()
                finishWithCurrentTranscript()
            }
        }
        if let error {
            let ns = error as NSError
            // Cancelación / fin de audio no es fallo si ya hay texto.
            if ns.domain == "kAFAssistantErrorDomain", ns.code == 1110 || ns.code == 216 {
                return
            }
            if transcript.isEmpty, case .listening = phase {
                phase = .error(error.localizedDescription)
                stopEngine()
            }
        }
    }

    private func finishWithCurrentTranscript() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopEngine()
        phase = .idle
        if !text.isEmpty {
            onFinished?(text)
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
