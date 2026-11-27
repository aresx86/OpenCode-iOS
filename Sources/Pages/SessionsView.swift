import SwiftUI

struct SessionsView: View {
    @EnvironmentObject var app: AppState

    @State private var sessions: [SessionInfo] = []
    @State private var activeIds: Set<String> = []
    @State private var searchText = ""
    @State private var loading = false
    @State private var errorMsg = ""
    @State private var showPicker = false
    @State private var chatTarget: SessionInfo?
    @State private var renameTarget: SessionInfo?
    @State private var renameText = ""

    private var filtered: [SessionInfo] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return sessions }
        return sessions.filter {
            displayTitle($0).localizedCaseInsensitiveContains(q)
                || ($0.directory ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    private var groups: [SessionGroup] {
        groupSessions(filtered)
    }

    var body: some View {
        Group {
            if app.current == nil {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.secondaryText)
                    Text("请先在「连接」页选择一台服务器")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.secondaryText)
                }
            } else if sessions.isEmpty && !loading {
                VStack(spacing: 8) {
                    if !errorMsg.isEmpty {
                        Text(errorMsg)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.danger)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("暂无会话，点击右上角 + 新建")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.secondaryText)
                    }
                }
            } else {
                sessionList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.pageBackground)
        .navigationTitle(app.current?.displayName ?? "会话")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.pageBackground, for: .navigationBar)
        .searchable(text: $searchText, prompt: "搜索会话")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showPicker = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(app.current == nil)
            }
        }
        .refreshable { await load() }
        .task(id: "\(app.sessionsTick)-\(app.current?.id ?? "")") {
            await load()
        }
        .sheet(isPresented: $showPicker) {
            if let conn = app.current {
                DirectoryPickerView(conn: conn) { directory in
                    showPicker = false
                    Task { await createSession(directory: directory) }
                }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { chatTarget != nil },
            set: { if !$0 { chatTarget = nil } }
        )) {
            if let conn = app.current, let s = chatTarget {
                ChatView(conn: conn, session: s)
            }
        }
        .alert("重命名会话", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("会话名称", text: $renameText)
            Button("取消", role: .cancel) { renameTarget = nil }
            Button("确定") { doRename() }
        }
    }

    private var sessionList: some View {
        List {
            ForEach(groups) { g in
                Section(header: Text(g.count > 1 ? "\(g.shortName) · \(g.count)" : g.shortName)) {
                    ForEach(g.sessions, id: \.id) { s in
                        row(s)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.pageBackground)
    }

    private func row(_ s: SessionInfo) -> some View {
        let busy = isSessionBusy(s) || activeIds.contains(s.id)
        return HStack(spacing: 10) {
            Circle()
                .fill(busy ? Theme.success : Theme.success.opacity(0.001))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle(s))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.primaryText)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(timeLabel(s))
                        .font(.system(size: 11))
                        .foregroundColor(Theme.secondaryText)
                    if let model = s.model {
                        Text(model)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.secondaryText.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { chatTarget = s }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await delete(s) }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .contextMenu {
            Button("重命名") {
                renameTarget = s
                renameText = s.title ?? ""
            }
            Button("删除", role: .destructive) {
                Task { await delete(s) }
            }
        }
    }

    private func timeLabel(_ s: SessionInfo) -> String {
        var parts: [String] = []
        if let t = s.time, t.updated > 0 {
            parts.append(formatRelative(t.updated))
        }
        if busy(s) {
            parts.append("运行中")
        }
        return parts.joined(separator: " · ")
    }

    private func busy(_ s: SessionInfo) -> Bool {
        isSessionBusy(s) || activeIds.contains(s.id)
    }

    private func load() async {
        guard let conn = app.current else { return }
        loading = true
        errorMsg = ""
        let client = ApiClient(conn: conn)
        do {
            sessions = try await client.listSessions()
            activeIds = Set((try? await client.listActiveSessions()) ?? [])
        } catch {
            errorMsg = (error as? ApiError)?.message ?? "\(error)"
        }
        loading = false
    }

    private func createSession(directory: String) async {
        guard let conn = app.current else { return }
        do {
            let s = try await ApiClient(conn: conn).createSession(title: "", directory: directory)
            app.sessionsTick += 1
            chatTarget = s
        } catch {
            app.showToast((error as? ApiError)?.message ?? "\(error)")
        }
    }

    private func delete(_ s: SessionInfo) async {
        guard let conn = app.current else { return }
        do {
            try await ApiClient(conn: conn).deleteSession(sessionId: s.id)
            sessions.removeAll { $0.id == s.id }
        } catch {
            app.showToast((error as? ApiError)?.message ?? "\(error)")
        }
    }

    private func doRename() {
        guard let s = renameTarget, let conn = app.current else { return }
        let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renameTarget = nil
        guard !title.isEmpty else { return }
        Task {
            do {
                try await ApiClient(conn: conn).renameSession(sessionId: s.id, title: title)
                await load()
            } catch {
                app.showToast((error as? ApiError)?.message ?? "\(error)")
            }
        }
    }
}
