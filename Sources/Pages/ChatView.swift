import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

enum ChatImageCache {
    static let cache = NSCache<NSString, UIImage>()

    static func image(fromDataUrl dataUrl: String) -> UIImage? {
        if let cached = cache.object(forKey: dataUrl as NSString) {
            return cached
        }
        guard let range = dataUrl.range(of: ";base64,") else { return nil }
        let b64 = String(dataUrl[range.upperBound...])
        guard let data = Data(base64Encoded: b64), let img = UIImage(data: data) else { return nil }
        cache.setObject(img, forKey: dataUrl as NSString)
        return img
    }
}

struct ChatView: View {
    let conn: Connection
    let session: SessionInfo

    @EnvironmentObject var app: AppState
    @StateObject private var state: ChatState
    @State private var showAgentPicker = false
    @State private var showModelPicker = false
    @State private var showAttachMenu = false
    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    @State private var pickedItems: [PhotosPickerItem] = []

    init(conn: Connection, session: SessionInfo) {
        self.conn = conn
        self.session = session
        _state = StateObject(wrappedValue: ChatState(
            conn: conn,
            sessionId: session.id,
            initialTitle: displayTitle(session)
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            if !state.errText.isEmpty {
                errorBanner
            }
            ForEach(state.pending) { p in
                PermissionCard(p: p) { response in
                    state.reply(p, response: response)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }
            messages
            agentModelChips
            attachmentChips
            inputBar
        }
        .background(Theme.pageBackground)
        .navigationTitle(state.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.pageBackground, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(state.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.primaryText)
                        .lineLimit(1)
                    if state.busy {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Theme.accent)
                            Text("执行中…")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.accent)
                        }
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 8) {
                    if state.busy {
                        Button {
                            state.stopAgent()
                        } label: {
                            Text("停止")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.danger)
                        }
                    }
                    Button {
                        state.toggleSystem()
                    } label: {
                        HStack(spacing: 4) {
                            Text(state.showSystem ? "隐藏" : "显示")
                                .font(.system(size: 11))
                                .foregroundColor(state.showSystem ? Theme.secondaryText : Theme.accent)
                            if !state.showSystem && state.hiddenCount > 0 {
                                Text("\(state.hiddenCount)")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(hex: "#0B1220"))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Theme.accent, in: Capsule())
                            }
                        }
                    }
                }
            }
        }
        .onAppear { state.start() }
        .onDisappear { state.stop() }
        .onChange(of: state.toast) { t in
            if let t {
                app.showToast(t)
                state.toast = nil
            }
        }
        .sheet(isPresented: $showAgentPicker) {
            AgentPickerSheet(state: state)
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerSheet(state: state)
        }
        .confirmationDialog("添加附件", isPresented: $showAttachMenu, titleVisibility: .visible) {
            Button("图片（png / jpeg / gif / webp）") {
                showPhotoPicker = true
            }
            Button("文件（文档、PDF、文本等）") {
                showFilePicker = true
            }
            Button("取消", role: .cancel) {}
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickedItems, matching: .images)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if let urls = try? result.get() {
                importFiles(urls)
            }
        }
        .onChange(of: pickedItems) { items in
            guard !items.isEmpty else { return }
            Task {
                let now = Int(Date().timeIntervalSince1970 * 1000)
                for (i, item) in items.enumerated() {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                    let type = item.supportedContentTypes.first
                    let mime = type?.preferredMIMEType ?? "image/jpeg"
                    let ext = type?.preferredFilenameExtension ?? "jpg"
                    state.addAttachment(data: data, mime: mime, name: "photo_\(now)_\(i).\(ext)")
                }
                pickedItems = []
            }
        }
    }

    private func importFiles(_ urls: [URL]) {
        for url in urls {
            let secured = url.startAccessingSecurityScopedResource()
            defer {
                if secured {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            guard let data = try? Data(contentsOf: url) else {
                app.showToast("读取文件失败：\(url.lastPathComponent)")
                continue
            }
            let name = url.lastPathComponent
            state.addAttachment(data: data, mime: state.mimeFromName(name), name: name)
        }
    }

    private var errorBanner: some View {
        Text(state.errText)
            .font(.system(size: 12))
            .foregroundColor(Theme.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            .onTapGesture { state.errText = "" }
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if state.loading && state.items.isEmpty {
                        ProgressView()
                            .tint(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if state.items.isEmpty && !state.busy && state.errText.isEmpty {
                        emptyState
                    }
                    ForEach(state.items) { item in
                        messageRow(item)
                            .id(item.id)
                    }
                    if state.busy && !state.sending {
                        thinkingRow
                            .id("thinking_indicator")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            .onChange(of: state.items.count) { _ in
                let target = state.items.last?.id ?? "thinking_indicator"
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(target, anchor: .bottom)
                }
            }
            .onChange(of: state.busy) { _ in
                let target = state.items.last?.id ?? "thinking_indicator"
                proxy.scrollTo(target, anchor: .bottom)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundColor(Theme.secondaryText)
            Text("输入任务，AI 开始工作")
                .font(.system(size: 13))
                .foregroundColor(Theme.secondaryText)
            Text("它会读代码、改文件、执行命令——敏感操作会先请求你的许可")
                .font(.system(size: 11))
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var thinkingRow: some View {
        Group {
            if state.isThinkingNow() {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.accent)
                    Text("AI 正在思考…")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.secondaryText)
                }
            } else {
                Text("▍")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func messageRow(_ item: ChatItem) -> some View {
        if item.isTool {
            ToolCard(item: item, state: state)
        } else {
            HStack(alignment: .top) {
                if item.isUser {
                    Spacer(minLength: 40)
                    userColumn(item)
                } else {
                    assistantColumn(item)
                    Spacer(minLength: 40)
                }
            }
        }
    }

    private func userColumn(_ item: ChatItem) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !item.text.isEmpty {
                Text(isSystemInjected(item) ? "[系统注入内容]" : item.text)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.userBubble))
                    .textSelection(.enabled)
            }
            if !item.fileUrl.isEmpty {
                ChatFileView(item: item)
            }
        }
    }

    private func assistantColumn(_ item: ChatItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !item.reasoning.isEmpty {
                ReasoningCard(item: item, openSet: $state.openReasoning)
            }
            if !item.text.isEmpty {
                MarkdownView(text: item.text)
            }
            if !item.fileUrl.isEmpty {
                ChatFileView(item: item)
            }
        }
    }

    private var agentModelChips: some View {
        HStack(spacing: 8) {
            Button {
                showAgentPicker = true
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(state.agentColor)
                        .frame(width: 8, height: 8)
                    Text(state.agentName.isEmpty ? "build" : state.agentName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.primaryText)
                        .lineLimit(1)
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.secondaryText)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.inputBackground))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(state.agentColor, lineWidth: 1))
            }

            Button {
                showModelPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(state.modelLabel)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.secondaryText)
                        .lineLimit(1)
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.secondaryText)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.inputBackground))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private var attachmentChips: some View {
        Group {
            if !state.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(state.attachments, id: \.dataUrl) { a in
                            attachmentChip(a)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 6)
            }
        }
    }

    private func attachmentChip(_ a: PendingAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if a.isImage, let img = ChatImageCache.image(fromDataUrl: a.dataUrl) {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .cornerRadius(10)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "doc")
                            .font(.system(size: 14))
                        Text(a.name)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.primaryText)
                            .lineLimit(1)
                            .frame(maxWidth: 90)
                    }
                    .frame(height: 56)
                    .padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cardBackground))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder, lineWidth: 1))
                }
            }
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Color(hex: "#CC0B1220"), in: Circle())
                .offset(x: 6, y: -6)
                .onTapGesture {
                    state.removeAttachment(a)
                }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                showAttachMenu = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18))
                    .foregroundColor(Theme.primaryText)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.cardBackground))
                    .overlay(Circle().stroke(Theme.cardBorder, lineWidth: 1))
            }

            TextEditor(text: $state.input)
                .font(.system(size: 14))
                .foregroundColor(Theme.primaryText)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 40, maxHeight: 120)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 18).fill(Theme.cardBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if state.input.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 14))
                            .foregroundColor(Theme.secondaryText)
                            .padding(.leading, 16)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                }

            Button {
                state.toggleVoice()
            } label: {
                Group {
                    if state.listening {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "mic")
                            .font(.system(size: 18))
                            .foregroundColor(Theme.primaryText)
                    }
                }
                .frame(width: 44, height: 44)
                .background(Circle().fill(state.listening ? Theme.danger : Theme.cardBackground))
                .overlay(Circle().stroke(state.listening ? Theme.danger : Theme.cardBorder, lineWidth: 1))
            }

            Button {
                state.send()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16))
                    .foregroundColor(state.busy || state.sending ? Theme.secondaryText : Color(hex: "#0F172A"))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(state.busy || state.sending ? Theme.cardBackground : Theme.accent))
            }
            .disabled(state.busy || state.sending)
            .padding(.trailing, 4)
        }
        .padding(.leading, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var placeholder: String {
        if state.listening { return "正在聆听…" }
        if state.busy { return "执行中，请等待…" }
        return "输入消息…"
    }
}

// MARK: - Sub views

private struct ReasoningCard: View {
    let item: ChatItem
    @Binding var openSet: Set<String>

    private var open: Bool {
        openSet.contains(item.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                if open {
                    openSet.remove(item.id)
                } else {
                    openSet.insert(item.id)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 11))
                    Text("思考过程")
                        .font(.system(size: 11))
                    Spacer()
                    Text(open ? "收起 ▴" : "展开 ▾")
                        .font(.system(size: 10))
                }
                .foregroundColor(Theme.secondaryText)
            }
            if open {
                Text(item.reasoning)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder, lineWidth: 1))
    }
}

struct ToolCard: View {
    let item: ChatItem
    @ObservedObject var state: ChatState

    private var expanded: Bool {
        state.expandedTools.contains(item.id)
    }

    private var hasDiff: Bool {
        state.hasDiff(item)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if expanded {
                    state.expandedTools.remove(item.id)
                } else {
                    state.expandedTools.insert(item.id)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.primaryText)
                    Text(item.toolName)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.primaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(state.toolStateLabel(item.toolState))
                        .font(.system(size: 11))
                        .foregroundColor(state.toolStateColor(item.toolState))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(hex: "#0B1220"), in: Capsule())
                }
            }

            if !item.commandText.isEmpty {
                Text("$ " + item.commandText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(2)
                    .textSelection(.enabled)
            } else if !item.filePath.isEmpty {
                Text(item.filePath)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            if expanded {
                if hasDiff {
                    DiffView(
                        filePath: item.filePath,
                        diffOld: item.diffOld,
                        diffNew: item.diffNew,
                        diffPatch: item.diffPatch
                    )
                }
                if !item.toolOutput.isEmpty {
                    Text(item.toolOutput)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.secondaryText)
                        .lineLimit(24)
                        .textSelection(.enabled)
                }
            }

            if hasDiff || !item.toolOutput.isEmpty {
                Button {
                    if expanded {
                        state.expandedTools.remove(item.id)
                    } else {
                        state.expandedTools.insert(item.id)
                    }
                } label: {
                    Text(expanded
                         ? "收起 ▴"
                         : (hasDiff && item.toolOutput.isEmpty ? "查看差异 ▾" : "查看输出 ▾"))
                        .font(.system(size: 10))
                        .foregroundColor(Theme.accent)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder, lineWidth: 1))
    }
}

struct ChatFileView: View {
    let item: ChatItem

    private var isImage: Bool {
        ["image/png", "image/jpeg", "image/gif", "image/webp"].contains(item.fileMime)
    }

    var body: some View {
        if isImage, let img = ChatImageCache.image(fromDataUrl: item.fileUrl) {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 200, maxHeight: 280)
                .cornerRadius(12)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "doc")
                    .font(.system(size: 14))
                Text(item.fileName.isEmpty ? "附件" : item.fileName)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12).fill(item.isUser ? Theme.userBubble : Theme.cardBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(item.isUser ? Color.clear : Theme.cardBorder, lineWidth: 1)
            )
        }
    }
}

struct PermissionCard: View {
    let p: PermissionRequest
    let onReply: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.warning)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 8) {
                Text("权限请求 · \(p.action ?? "")")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.warning)
                if let resources = p.resources, !resources.isEmpty {
                    Text(resources.joined(separator: "\n"))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.primaryText)
                        .lineLimit(6)
                }
                if let message = p.message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.secondaryText)
                }
                HStack(spacing: 8) {
                    Button {
                        onReply("reject")
                    } label: {
                        Text("拒绝")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.danger)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "#0B1220")))
                    }
                    Button {
                        onReply("once")
                    } label: {
                        Text("本次允许")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "#0B1220")))
                    }
                    Button {
                        onReply("always")
                    } label: {
                        Text("总是允许")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "#0F172A"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent))
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#6B4A12"), lineWidth: 1))
    }
}

// MARK: - Pickers

struct AgentPickerSheet: View {
    @ObservedObject var state: ChatState
    @Environment(\.dismiss) private var dismiss

    @State private var agents: [AgentOption] = []
    @State private var loading = true
    @State private var err = ""

    private var options: [AgentOption] {
        agents.filter { $0.mode != "subagent" && !$0.hidden }
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView().tint(Theme.accent)
                } else if !err.isEmpty {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.danger)
                } else if options.isEmpty {
                    Text("没有可用的智能体")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondaryText)
                } else {
                    List(options) { a in
                        Button {
                            state.applyAgent(a.id)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(a.name)
                                        .foregroundColor(Theme.primaryText)
                                    if !a.description.isEmpty {
                                        Text(a.description)
                                            .font(.system(size: 11))
                                            .foregroundColor(Theme.secondaryText)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                if a.id == state.agentName {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Theme.accent)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.pageBackground)
            .navigationTitle("选择智能体")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.pageBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                do {
                    agents = try await state.client.listAgents()
                } catch {
                    err = (error as? ApiError)?.message ?? "\(error)"
                }
                loading = false
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct ModelGroup: Identifiable {
    let provider: String
    let models: [ModelOption]
    var id: String { provider }
}

struct ModelPickerSheet: View {
    @ObservedObject var state: ChatState
    @Environment(\.dismiss) private var dismiss

    @State private var models: [ModelOption] = []
    @State private var loading = true
    @State private var err = ""
    @State private var search = ""

    private var filteredGroups: [ModelGroup] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = models.filter { m in
            q.isEmpty
                || m.name.localizedCaseInsensitiveContains(q)
                || m.id.localizedCaseInsensitiveContains(q)
                || m.providerID.localizedCaseInsensitiveContains(q)
        }
        var order: [String] = []
        var map: [String: [ModelOption]] = [:]
        for m in filtered {
            if map[m.providerID] == nil {
                order.append(m.providerID)
                map[m.providerID] = []
            }
            map[m.providerID]?.append(m)
        }
        return order.map { ModelGroup(provider: $0, models: map[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView().tint(Theme.accent)
                } else if !err.isEmpty {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.danger)
                } else if filteredGroups.isEmpty {
                    Text("没有可用模型")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondaryText)
                } else {
                    modelList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.pageBackground)
            .navigationTitle("选择模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.pageBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .searchable(text: $search, prompt: "搜索模型或供应商…")
            .task {
                do {
                    models = try await state.client.listModels()
                } catch {
                    err = (error as? ApiError)?.message ?? "\(error)"
                }
                loading = false
            }
        }
        .preferredColorScheme(.dark)
    }

    private var modelList: some View {
        List {
            ForEach(filteredGroups) { group in
                Section(header: Text(group.provider)) {
                    ForEach(group.models) { m in
                        Button {
                            state.applyModel(m.id, m.providerID)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.name.isEmpty ? m.id : m.name)
                                        .foregroundColor(Theme.primaryText)
                                    Text(m.providerID)
                                        .font(.system(size: 11))
                                        .foregroundColor(Theme.secondaryText)
                                }
                                Spacer()
                                if m.id == state.modelLabel {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Theme.accent)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.pageBackground)
    }
}
