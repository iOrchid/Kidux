import AVFoundation
import Foundation
import Speech

/// S18-04 — 发现页语音 → 自然语言筛选
@MainActor
final class DiscoverSpeechInputService {
    static let shared = DiscoverSpeechInputService()

    private(set) var isListening = false

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private init() {}

    func authorizationStatus() -> (speech: SFSpeechRecognizerAuthorizationStatus, mic: AVAuthorizationStatus) {
        (SFSpeechRecognizer.authorizationStatus(), AVCaptureDevice.authorizationStatus(for: .audio))
    }

    func requestAuthorization() async -> Bool {
        // SFSpeechRecognizer 回调不在 MainActor；不能在 @MainActor 方法内直接 resume continuation，
        // 否则会触发 _swift_task_checkIsolatedSwift / EXC_BREAKPOINT（点语音图标闪退）。
        let speechGranted = await Self.requestSpeechAuthorizationOffMainActor()
        guard speechGranted else { return false }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    /// 在非 MainActor 上下文请求语音识别授权，避免回调线程隔离断言崩溃。
    private nonisolated static func requestSpeechAuthorizationOffMainActor() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let lock = NSLock()
            var resumed = false
            SFSpeechRecognizer.requestAuthorization { status in
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startListening(
        locale: Locale = Locale(identifier: "zh-CN"),
        onPartial: @escaping @Sendable (String) -> Void,
        onFinal: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) throws {
        guard !isListening else { return }
        stopListening()

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            onError("当前语言语音识别不可用")
            return
        }

        speechRecognizer = recognizer
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.isListening else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        onFinal(text)
                    } else {
                        onPartial(text)
                    }
                }
                if let error {
                    onError(error.localizedDescription)
                }
            }
        }
    }

    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }
}
