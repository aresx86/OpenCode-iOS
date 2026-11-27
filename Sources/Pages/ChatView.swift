import SwiftUI

struct ChatView: View {
    let conn: Connection
    let session: SessionInfo

    @State private var items: [ChatItem] = []
    @State private var loading = true
    @State private var errorMsg = ""

    var body: some View {
        Group {
            if loading {
                ProgressView().tint(Theme.accent)
            } else if !errorMsg.isEmpty {
                Text(errorMsg)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.danger)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                chatList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.pageBackground)
        .navigationTitle(displayTitle(session))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.pageBackground, for: .navigationBar)
        .task { await load() }
        .refreshable { await load() }
    }

    private var chatList: some View {
        ScrollView {
            ScrollViewReader { proxy in
                LazyVStack(alignment: .leading, spacing: 10) {
                    if items.isEmpty {
                        Text("暂无消息")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    ForEach(items) { item in
                        ChatRowView(item: item)
                            .id(item.id)
                    }
                }
                .padding(12)
                .onChange(of: items.count) { _ in
                    if let last = items.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func load() async {
        loading = items.isEmpty
        errorMsg = ""
        do {
            items = try await ApiClient(conn: conn).listMessages(session.id)
        } catch {
            errorMsg = (error as? ApiError)?.message ?? "\(error)"
        }
        loading = false
    }
}

struct ChatRowView: View {
    let item: ChatItem

    var body: some View {
        if item.isTool {
            toolRow
        } else if item.isFile {
            fileRow
        } else if item.isUser {
            userBubble
        } else {
            assistantBlock
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 48)
            Text(isSystemInjected(item) ? "[系统注入内容]" : stripSystemInjected(item.text))
                .font(.system(size: 14))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.userBubble))
        }
    }

    private var assistantBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !item.reasoning.isEmpty {
                ReasoningView(text: item.reasoning)
            }
            if !item.text.isEmpty {
                Text(isSystemInjected(item) && item.role == "user" ? "[系统注入内容]" : item.text)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.primaryText)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardBackground))
            }
        }
    }

    private var toolRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 11))
                Text(item.toolName)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(stateText)
                    .font(.system(size: 11))
            }
            .foregroundColor(stateColor)

            if !item.commandText.isEmpty {
                Text(item.commandText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(3)
            }
            if !item.filePath.isEmpty {
                Text(item.filePath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(2)
            }
            if !item.toolOutput.isEmpty {
                Text(item.toolOutput)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.reasoningText)
                    .lineLimit(4)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.inputBackground))
    }

    private var fileRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "paperclip")
                .font(.system(size: 12))
            Text(item.fileName.isEmpty ? "附件" : item.fileName)
                .font(.system(size: 12))
        }
        .foregroundColor(Theme.secondaryText)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.inputBackground))
    }

    private var stateText: String {
        switch item.toolState {
        case "running", "pending": return "运行中"
        case "completed", "done": return "完成"
        case "error", "failed": return "失败"
        default: return item.toolState.isEmpty ? "—" : item.toolState
        }
    }

    private var stateColor: Color {
        switch item.toolState {
        case "running", "pending": return Theme.warning
        case "completed", "done": return Theme.success
        case "error", "failed": return Theme.danger
        default: return Theme.secondaryText
        }
    }
}

struct ReasoningView: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                    Text("思考过程")
                        .font(.system(size: 12))
                }
                .foregroundColor(Theme.secondaryText)
            }
            if expanded {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.reasoningText)
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.inputBackground.opacity(0.6)))
    }
}
