import SwiftUI

struct ConnectionsView: View {
    @EnvironmentObject var app: AppState
    @State private var testingId = ""
    @State private var editTarget: String?
    @State private var renameTarget: Connection?
    @State private var renameText = ""
    @State private var deleteTarget: Connection?

    var body: some View {
        Group {
            if app.connections.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.pageBackground)
        .navigationTitle("连接")
        .toolbarBackground(Theme.pageBackground, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            addButton
        }
        .onAppear { app.reload() }
        .onChange(of: editTarget) { t in
            if t == nil { app.reload() }
        }
        .navigationDestination(isPresented: Binding(
            get: { editTarget != nil },
            set: { if !$0 { editTarget = nil } }
        )) {
            EditConnectionView(editId: editTarget ?? "")
        }
        .alert("重命名连接", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("显示名称，例如「公司台式机」", text: $renameText)
            Button("取消", role: .cancel) { renameTarget = nil }
            Button("确定") { doRename() }
        }
        .alert("删除连接", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("取消", role: .cancel) { deleteTarget = nil }
            Button("删除", role: .destructive) {
                if let c = deleteTarget {
                    ConnectionStore.shared.remove(c.id)
                    if app.current?.id == c.id { app.current = nil }
                    app.reload()
                }
            }
        } message: {
            Text("确定删除连接「\(deleteTarget?.displayName ?? "")」吗？")
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(app.connections, id: \.id) { c in
                    card(c)
                }
                Text("点击连接设为当前使用 · 长按或用力按压可编辑 / 重命名 / 删除")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private func card(_ c: Connection) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(c.apiVersion > 0 ? Theme.success : Theme.secondaryText.opacity(0.5))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(c.displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.primaryText)
                    .lineLimit(1)
                Text(c.baseUrl)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if testingId == c.id {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.accent)
            } else {
                Text(c.apiVersion == 0
                     ? "待检测"
                     : "V\(c.apiVersion)" + (c.serverVersion.isEmpty ? "" : " · \(c.serverVersion)"))
                    .font(.system(size: 11))
                    .foregroundColor(c.apiVersion > 0 ? Theme.accent : Theme.secondaryText)
            }
        }
        .padding(16)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { openConnection(c) }
        .contextMenu {
            Button("编辑") { editTarget = c.id }
            Button("重命名") {
                renameTarget = c
                renameText = c.name
            }
            Divider()
            Button("删除", role: .destructive) { deleteTarget = c }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.3")
                .font(.system(size: 44))
                .foregroundColor(Theme.accent)
            Text("连接你的 opencode 服务器")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Theme.primaryText)
            VStack(alignment: .leading, spacing: 6) {
                Text("1. 电脑上运行 opencode serve --hostname 0.0.0.0 --port 4096")
                Text("2. 手机与电脑连同一网络（或用 Tailscale / 隧道）")
                Text("3. 点击下方按钮，填入服务器地址")
            }
            .font(.system(size: 12))
            .foregroundColor(Theme.secondaryText)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 24)
    }

    private var addButton: some View {
        Button {
            editTarget = ""
        } label: {
            Text(app.connections.isEmpty ? "添加连接" : "+ 新增连接")
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(app.connections.isEmpty ? Theme.accent : Theme.cardBackground)
                )
                .foregroundColor(app.connections.isEmpty ? Color(hex: "#0F172A") : Theme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func openConnection(_ c: Connection) {
        guard testingId.isEmpty else { return }
        testingId = c.id
        Task {
            await app.openConnection(c)
            testingId = ""
        }
    }

    private func doRename() {
        guard let c = renameTarget else { return }
        var all = ConnectionStore.shared.loadAll()
        if let idx = all.firstIndex(where: { $0.id == c.id }) {
            let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
            all[idx].name = trimmed.isEmpty ? trimSlash(all[idx].baseUrl) : trimmed
            ConnectionStore.shared.saveAll(all)
            app.reload()
        }
        renameTarget = nil
    }
}
