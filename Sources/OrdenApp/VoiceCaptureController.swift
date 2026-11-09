import Foundation
import AVFoundation
import Speech
import AppKit
import OrdenCore

/// Push-to-talk local.
/// Sin `@MainActor` en la clase: el tap de audio corre en realtime y no puede
/// heredar aislamiento MainActor. El estado UI se publica solo en el main.
final class VoiceCaptureController: ObservableObject, @unchecked Sendable {
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
    var onFinished: ((String) -> Void)?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var finishWorkItem: DispatchWorkItem?
    private var speechRecognizer: SFSpeechRecognizer? {
        if L10n.activeLanguage == .english {
            return SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
                ?? SFSpeechRecognizer(locale: Locale(identifier: "en-GB"))
                ?? SFSpeechRecognizer(locale: Locale(identifier: "en"))
        } else {
            return SFSpeechRecognizer(locale: Locale(identifier: "es-MX"))
                ?? SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
                ?? SFSpeechRecognizer(locale: Locale(identifier: "es"))
        }
    }

    var isListening: Bool {
        if case .listening = phase { return true }
        return false
    }

    var statusLabel: String {
        switch phase {
        case .idle: return L10n.s("Mantén el micrófono o ⌃Espacio", "Hold microphone or ⌃Space")
        case .requestingPermission: return L10n.s("Pidiendo permiso…", "Requesting permission…")
        case .listening: return transcript.isEmpty ? L10n.s("Escuchando…", "Listening…") : transcript
        case .processing: return L10n.s("Procesando…", "Processing…")
        case .error(let msg): return msg
        }
    }

    func beginPushToTalk() {
        finishWorkItem?.cancel()
        transcript = ""
        phase = .requestingPermission
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                VoiceCaptureController.shared.didReceiveSpeechAuthorization(status)
            }
        }
    }

    func endPushToTalk() {
        DispatchQueue.main.async {
            VoiceCaptureController.shared.endPushToTalkOnMain()
        }
    }

    func cancel() {
        DispatchQueue.main.async {
            let s = VoiceCaptureController.shared
            s.finishWorkItem?.cancel()
            s.finishWorkItem = nil
            s.stopEngine()
            s.transcript = ""
            s.phase = .idle
        }
    }

    // MARK: - Auth / mic

    private func didReceiveSpeechAuthorization(_ status: SFSpeechRecognizerAuthorizationStatus) {
        guard status == .authorized else {
            phase = .error(L10n.s("Activa Reconocimiento de voz en Ajustes del sistema", "Enable Speech Recognition in System Settings"))
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
            phase = .error(L10n.s("Activa el micrófono para Findaro en Ajustes del sistema", "Enable microphone for Findaro in System Settings"))
            return
        }
        startEngine()
    }

    private func endPushToTalkOnMain() {
        guard phase == .listening || phase == .requestingPermission || phase == .processing else {
            return
        }
        if phase == .requestingPermission {
            finishWorkItem?.cancel()
            stopEngine()
            transcript = ""
            phase = .idle
            return
        }
        phase = .processing
        recognitionRequest?.endAudio()
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        finishWorkItem?.cancel()
        let work = DispatchWorkItem {
            VoiceCaptureController.shared.finishWithCurrentTranscript()
        }
        finishWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    // MARK: - Engine

    private func startEngine() {
        stopEngine()
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            phase = .error(L10n.s("Reconocimiento de voz no disponible en este Mac", "Speech recognition not available on this Mac"))
            return
        }

        // Privacidad: solo reconocimiento on-device. Sin soporte local → no iniciar.
        guard recognizer.supportsOnDeviceRecognition else {
            phase = .error(
                L10n.s(
                    "Este Mac no admite reconocimiento de voz local. No inicio el dictado para proteger tu privacidad.",
                    "This Mac does not support on-device speech recognition. Dictation not started to protect privacy."
                )
            )
            return
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            phase = .error(L10n.s("No hay micrófono disponible", "No microphone available"))
            return
        }

        // Solo append — sin self. Corre en realtime audio thread.
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
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let nsError = error as NSError?
            DispatchQueue.main.async {
                VoiceCaptureController.shared.didReceiveRecognition(
                    text: text,
                    isFinal: isFinal,
                    error: nsError
                )
            }
        }
    }

    private func didReceiveRecognition(text: String?, isFinal: Bool, error: NSError?) {
        if let text {
            transcript = text
            if isFinal, case .processing = phase {
                finishWorkItem?.cancel()
                finishWithCurrentTranscript()
            }
        }
        if let error {
            if error.domain == "kAFAssistantErrorDomain", error.code == 1110 || error.code == 216 {
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
