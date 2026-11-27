import AVFoundation
import Speech
import UIKit

@MainActor
final class VoiceInput: NSObject {
    var onText: (String) -> Void = { _ in }
    var onListeningChange: (Bool) -> Void = { _ in }
    var onError: (String) -> Void = { _ in }
    var onAutoStop: (String) -> Void = { _ in }

    private(set) var listening = false

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    private var baseText = ""
    private var settled = ""
    private var partial = ""

    private var lastActivity = Date()
    private var startedAt = Date()
    private var watchdog: Timer?

    private let silenceLimit: TimeInterval = 3.0
    private let maxDuration: TimeInterval = 60.0

    override private init() {
        super.init()
    }

    static let shared = VoiceInput()

    func start(base: String) {
        guard !listening else { return }
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                guard status == .authorized else {
                    self.onError("未授予语音识别权限，无法使用语音输入")
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        guard granted else {
                            self.onError("未授予麦克风权限，无法使用语音输入")
                            return
                        }
                        self.beginRecording(base: base)
                    }
                }
            }
        }
    }

    private func beginRecording(base: String) {
        let rec = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")) ?? SFSpeechRecognizer()
        guard let rec, rec.isAvailable else {
            onError("语音识别暂不可用，请稍后再试")
            return
        }
        recognizer = rec

        var b = base
        if let last = b.last, last != " " && last != "\n" {
            b += " "
        }
        baseText = b
        settled = ""
        partial = ""

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else {
                onError("语音识别启动失败：无可用麦克风")
                return
            }

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            request = req

            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }

            engine.prepare()
            try engine.start()

            task = rec.recognitionTask(with: req) { [weak self] result, error in
                DispatchQueue.main.async {
                    self?.handleResult(result, error: error)
                }
            }

            listening = true
            startedAt = Date()
            lastActivity = Date()
            startWatchdog()
            onListeningChange(true)
        } catch {
            cleanupAudio()
            onError("语音识别启动失败：\(error.localizedDescription)")
        }
    }

    private func handleResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let text = result.bestTranscription.formattedString
            if result.isFinal {
                settled += text
                partial = ""
            } else {
                partial = text
            }
            lastActivity = Date()
            onText(baseText + settled + partial)
        }
        if let error {
            if listening {
                finishListening(auto: true)
                onError("语音识别出错：\(error.localizedDescription)")
            }
        }
    }

    func stop() {
        guard listening else { return }
        request?.endAudio()
        task?.finish()
        finishListening(auto: false)
    }

    func destroy() {
        task?.cancel()
        task = nil
        request = nil
        cleanupAudio()
        listening = false
        watchdog?.invalidate()
        watchdog = nil
    }

    private func finishListening(auto: Bool) {
        guard listening else { return }
        listening = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        watchdog?.invalidate()
        watchdog = nil
        onListeningChange(false)
        if auto {
            onAutoStop("语音识别已结束")
        }
    }

    private func cleanupAudio() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.listening else { return }
                let now = Date()
                if now.timeIntervalSince(self.startedAt) >= self.maxDuration {
                    self.stop()
                    self.onAutoStop("已达 60 秒上限，语音输入结束")
                } else if now.timeIntervalSince(self.lastActivity) >= self.silenceLimit {
                    self.stop()
                    self.onAutoStop("语音识别已结束")
                }
            }
        }
    }
}
