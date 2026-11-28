import Foundation
import SwiftUI

@MainActor
final class ChatState: ObservableObject {
    @Published var items: [ChatItem] = []
    @Published var busy = false
    @Published var sending = false
    @Published var input = ""
    @Published var pending: [PermissionRequest] = []
    @Published var errText = ""
    @Published var expandedTools: Set<String> = []
    @Published var openReasoning: Set<String> = []
    @Published var showSystem: Bool
    @Published var hiddenCount = 0
    @Published var agentName = ""
    @Published var modelLabel = "default"
    @Published var title: String
    @Published var loading = true
    @Published var toast: String?
    @Published var listening = false
    @Published var attachments: [PendingAttachment] = []

    let conn: Connection
    let sessionId: String
    let client: ApiClient

    private let voice = VoiceInput.shared

    private var stream: EventStream?
    private var restartCount = 0
    private var destroyed = false
    private var started = false
    private var reloadTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var busySince = Date(timeIntervalSince1970: 0)

    init(conn: Connection, sessionId: String, initialTitle: String) {
        self.conn = conn
        self.sessionId = sessionId
        self.client = ApiClient(conn: conn)
        self.title = initialTitle
        self.showSystem = ConnectionStore.shared.showSystem
        voice.onText = { [weak self] full in
            self?.input = full
        }
        voice.onListeningChange = { [weak self] l in
            self?.listening = l
            if l {
                self?.toast = "正在聆听，再次点击麦克风结束"
            }
        }
        voice.onError = { [weak self] msg in
            self?.toast = msg
        }
        voice.onAutoStop = { [weak self] msg in
            self?.toast = msg
        }
    }

    var agentColor: Color {
        Theme.agentColor(agentName.isEmpty ? "build" : agentName)
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        reloadMessages()
        reloadPermissions()
        loadSessionMeta()
        startStream()
        startPolling()
    }

    func stop() {
        destroyed = true
        stream?.stop()
        stream = nil
        reloadTask?.cancel()
        retryTask?.cancel()
        restartTask?.cancel()
        pollTask?.cancel()
        voice.destroy()
    }

    // MARK: - Voice

    func toggleVoice() {
        if voice.listening {
            voice.stop()
            return
        }
        guard !listening else { return }
        voice.start(base: input)
    }

    // MARK: - Attachments

    func addAttachment(data: Data, mime: String, name: String) {
        guard attachments.count < 6 else {
            toast = "最多添加 6 个附件"
            return
        }
        guard data.count <= 15 * 1024 * 1024 else {
            toast = "文件超过 15MB：\(name)"
            return
        }
        let dataUrl = "data:\(mime);base64," + data.base64EncodedString()
        attachments.append(PendingAttachment(name: name, mime: mime, dataUrl: dataUrl, isImage: isImageMime(mime)))
    }

    func removeAttachment(_ a: PendingAttachment) {
        attachments.removeAll { $0.dataUrl == a.dataUrl && $0.name == a.name }
    }

    func isImageMime(_ mime: String) -> Bool {
        mime == "image/png" || mime == "image/jpeg" || mime == "image/gif" || mime == "image/webp"
    }

    func mimeFromName(_ name: String) -> String {
        let lower = name.lowercased()
        guard let dot = lower.lastIndex(of: ".") else { return "application/octet-stream" }
        let ext = String(lower[lower.index(after: dot)...])
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "pdf": return "application/pdf"
        case "txt", "md", "log": return "text/plain"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }

    // MARK: - Stream

    private func startStream() {
        guard !destroyed else { return }
        let s = EventStream(conn: conn)
        stream = s
        s.onEvent = { [weak self] name, data in
            self?.handleEvent(name, data)
        }
        s.onClosed = { [weak self] in
            self?.handleStreamClosed()
        }
        s.onStarted = { [weak self] in
            guard let self, !self.destroyed else { return }
            self.restartCount = 0
            self.scheduleReload()
        }
        s.start()
    }

    private func handleStreamClosed() {
        guard !destroyed else { return }
        restartCount += 1
        scheduleReload()
        let delay = UInt64(min(2000 * restartCount, 15000)) * 1_000_000
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !self.destroyed, !Task.isCancelled else { return }
            self.startStream()
        }
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { break }
                guard let self, !self.destroyed else { break }
                self.loadSessionMeta()
                if self.busy {
                    self.reloadPermissions()
                    self.scheduleReload()
                }
            }
        }
    }

    private func handleEvent(_ name: String, _ data: String) {
        restartCount = 0
        if name.contains("permission") {
            reloadPermissions()
            scheduleReload()
            return
        }
        if name == "session.status" {
            onStatusEvent(data)
            scheduleReload()
            return
        }
        if name == "session.idle" || name == "session.error" {
            busy = false
            reloadMessages()
            return
        }
        if name == "session.updated" || name == "session.renamed" {
            loadSessionMeta()
            return
        }
        if name == "session.inbox.enqueued" || name == "session.inbox.delivered"
            || name == "session.execution.started" {
            if eventForThisSession(data) {
                applyBusy(true)
                scheduleReload()
            }
            return
        }
        if name == "session.execution.succeeded" || name == "session.execution.failed"
            || name == "session.execution.aborted" {
            if eventForThisSession(data) {
                busy = false
            }
            reloadMessages()
            return
        }
        if name == "session.text.delta" || name == "session.reasoning.delta"
            || name == "session.text.started" || name == "session.text.ended"
            || name == "session.reasoning.started" || name == "session.reasoning.ended" {
            if eventForThisSession(data) {
                applyBusy(true)
                scheduleReload()
            }
            return
        }
        if name.contains("message") || name.contains("part") || name.hasPrefix("session.") {
            scheduleReload()
        }
    }

    private func eventForThisSession(_ data: String) -> Bool {
        guard let obj = jRoot(data) else { return true }
        if let d = jObj(obj, "data") {
            let sid = jStr(d, "sessionID")
            return sid.isEmpty || sid == sessionId
        }
        let sid = jStr(obj, "sessionID")
        return sid.isEmpty || sid == sessionId
    }

    private func onStatusEvent(_ data: String) {
        guard let obj = jRoot(data) else { return }
        let sid = jStr(obj, "sessionID")
        if sid != sessionId {
            return
        }
        let st = jObj(obj, "status")
        let t = st != nil ? jStr(st, "type") : ""
        if t == "busy" || t == "retry" {
            applyBusy(true)
        } else if t == "idle" {
            busy = false
        }
    }

    // MARK: - Data loading

    private func scheduleReload() {
        guard !destroyed else { return }
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, !self.destroyed, !Task.isCancelled else { return }
            self.reloadMessages()
        }
    }

    func loadSessionMeta() {
        guard !destroyed else { return }
        Task { [weak self] in
            guard let self, !self.destroyed else { return }
            do {
                let s = try await self.client.getSession(sessionId: self.sessionId)
                if self.destroyed { return }
                if let a = s.agent, !a.isEmpty {
                    self.agentName = a
                }
                if let m = s.model, !m.isEmpty {
                    self.modelLabel = m.components(separatedBy: "/").last ?? m
                }
                if let t = s.title, !t.isEmpty {
                    self.title = displayTitle(s)
                }
                guard !self.sending else { return }
                let ids = (try? await self.client.listActiveSessions()) ?? []
                if self.destroyed { return }
                self.applyBusy(ids.contains(self.sessionId) ? true : isSessionBusy(s))
            } catch {
            }
        }
    }

    private func applyBusy(_ running: Bool) {
        if running {
            if !busy {
                busySince = Date()
            }
            busy = true
        } else if Date().timeIntervalSince(busySince) > 15 {
            busy = false
        }
    }

    func reloadMessages() {
        guard !destroyed, !reloadingNow else { return }
        reloadingNow = true
        Task { [weak self] in
            await self?.doReloadMessages()
        }
    }

    private var reloadingNow = false

    private func doReloadMessages() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await self.client.listMessages(sessionId: self.sessionId)
                self.reloadingNow = false
                if self.destroyed { return }
                self.errText = ""
                self.items = self.filterItems(raw)
                self.loading = false
            } catch {
                self.reloadingNow = false
                if self.destroyed { return }
                if self.items.isEmpty {
                    self.errText = (error as? ApiError)?.message ?? "\(error)"
                }
                self.retryTask?.cancel()
                self.retryTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard let self, !self.destroyed, !Task.isCancelled else { return }
                    self.reloadMessages()
                }
            }
            self.loading = false
        }
    }

    func reloadPermissions() {
        guard !destroyed else { return }
        Task { [weak self] in
            guard let self, !self.destroyed else { return }
            let ps = (try? await self.client.listPermissions(sessionId: self.sessionId)) ?? []
            if !self.destroyed {
                self.pending = ps
            }
        }
    }

    // MARK: - Filtering (port of filterItems)

    private func copyItem(_ it: ChatItem, text: String, toolOutput: String) -> ChatItem {
        let n = ChatItem(key: it.key)
        n.role = it.role
        n.text = text
        n.reasoning = it.reasoning
        n.toolName = it.toolName
        n.toolState = it.toolState
        n.toolOutput = toolOutput
        n.filePath = it.filePath
        n.commandText = it.commandText
        n.diffOld = it.diffOld
        n.diffNew = it.diffNew
        n.diffPatch = it.diffPatch
        n.fileMime = it.fileMime
        n.fileUrl = it.fileUrl
        n.fileName = it.fileName
        n.created = it.created
        return n
    }

    private func filterItems(_ source: [ChatItem]) -> [ChatItem] {
        var out: [ChatItem] = []
        var stripped = 0
        for it in source {
            if showSystem {
                out.append(copyItem(it, text: it.text, toolOutput: it.toolOutput))
                continue
            }
            if it.role == "tool" {
                if it.toolName.contains("hindsight") {
                    stripped += 1
                    continue
                }
                let cleanedOut = stripSystemInjected(it.toolOutput)
                if cleanedOut != it.toolOutput {
                    stripped += countSystemInjected(it.toolOutput)
                }
                out.append(copyItem(it, text: it.text, toolOutput: cleanedOut))
                continue
            }
            let cleaned = stripSystemInjected(it.text)
            if cleaned != it.text {
                stripped += countSystemInjected(it.text)
            }
            if cleaned.isEmpty && it.reasoning.isEmpty {
                continue
            }
            out.append(copyItem(it, text: cleaned, toolOutput: it.toolOutput))
        }
        hiddenCount = stripped
        return out
    }

    // MARK: - Actions

    func toggleSystem() {
        showSystem.toggle()
        ConnectionStore.shared.showSystem = showSystem
        reloadMessages()
        toast = showSystem ? "已显示系统注入内容" : "已隐藏系统注入内容"
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = attachments
        if (text.isEmpty && files.isEmpty) || busy || sending {
            return
        }
        sending = true
        busy = true
        busySince = Date()
        let now = Int(Date().timeIntervalSince1970 * 1000)
        if !text.isEmpty {
            let optimistic = ChatItem(key: "pending_\(now)")
            optimistic.role = "user"
            optimistic.text = text
            items.append(optimistic)
        }
        for (i, a) in files.enumerated() {
            let f = ChatItem(key: "pending_\(now)_f\(i)")
            f.role = "user"
            f.fileMime = a.mime
            f.fileUrl = a.dataUrl
            f.fileName = a.name
            items.append(f)
        }
        input = ""
        attachments = []
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.client.prompt(sessionId: self.sessionId, text: text, attachments: files)
                self.sending = false
                self.reloadMessages()
                if self.conn.apiVersion == 1 {
                    self.busy = false
                }
            } catch {
                self.sending = false
                self.busy = false
                self.errText = (error as? ApiError)?.message ?? "\(error)"
            }
        }
    }

    func stopAgent() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.client.interrupt(sessionId: self.sessionId)
                self.busy = false
                self.reloadMessages()
            } catch {
                self.busy = false
            }
        }
    }

    func reply(_ p: PermissionRequest, response: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.client.replyPermission(sessionId: self.sessionId, requestId: p.id, response: response)
                self.reloadPermissions()
                self.scheduleReload()
            } catch {
                self.errText = (error as? ApiError)?.message ?? "\(error)"
            }
        }
    }

    func applyAgent(_ agentId: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.client.switchAgent(sessionId: self.sessionId, agentId: agentId)
                self.agentName = agentId
                let suffix = self.conn.apiVersion == 1 ? "（下次发送时生效）" : ""
                self.toast = "已选择智能体：\(agentId)\(suffix)"
            } catch {
                self.toast = (error as? ApiError)?.message ?? "\(error)"
            }
        }
    }

    func applyModel(_ modelId: String, _ providerId: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.client.switchModel(sessionId: self.sessionId, modelId: modelId, providerId: providerId)
                self.modelLabel = modelId
                let suffix = self.conn.apiVersion == 1 ? "（下次发送时生效）" : ""
                self.toast = "已选择模型：\(modelId)\(suffix)"
            } catch {
                self.toast = (error as? ApiError)?.message ?? "\(error)"
            }
        }
    }

    func hasDiff(_ item: ChatItem) -> Bool {
        !item.diffOld.isEmpty || !item.diffNew.isEmpty || !item.diffPatch.isEmpty
    }

    func isThinkingNow() -> Bool {
        if items.isEmpty {
            return true
        }
        return items.last?.role == "user"
    }

    func toolStateLabel(_ state: String) -> String {
        switch state {
        case "running": return "运行中"
        case "streaming": return "流式中"
        case "completed": return "完成"
        case "error": return "失败"
        default: return state.isEmpty ? "执行" : state
        }
    }

    func toolStateColor(_ state: String) -> Color {
        if state == "error" { return Theme.danger }
        if state == "completed" { return Theme.accent }
        return Theme.secondaryText
    }
}
