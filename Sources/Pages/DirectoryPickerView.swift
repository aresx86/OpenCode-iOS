import SwiftUI

struct DirectoryPickerView: View {
    let conn: Connection
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var knownDirs: [FsEntry] = []
    @State private var subDirs: [FsEntry] = []
    @State private var browseDir: String?
    @State private var loading = true
    @State private var errorMsg = ""

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView().tint(Theme.accent)
                } else if !errorMsg.isEmpty {
                    VStack(spacing: 8) {
                        Text(errorMsg)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.danger)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    dirList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.pageBackground)
            .navigationTitle("选择项目目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.pageBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .task { await load() }
        }
        .preferredColorScheme(.dark)
    }

    private var dirList: some View {
        List {
            if browseDir != nil {
                Section {
                    Button {
                        let parent = parentOf(browseDir ?? "")
                        if parent != browseDir {
                            Task { await browse(parent) }
                        }
                    } label: {
                        Label("上一级", systemImage: "chevron.up")
                            .foregroundColor(Theme.accent)
                    }
                }
                Section("服务器目录：\(browseDir ?? "/")") {
                    if subDirs.isEmpty {
                        Text("（无子目录）")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.secondaryText)
                    }
                    ForEach(subDirs) { e in
                        Button {
                            Task { await browse(e.path) }
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundColor(Theme.accent)
                                Text(e.name)
                                    .foregroundColor(Theme.primaryText)
                                    .lineLimit(1)
                                Spacer()
                                Text("选择")
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.accent)
                            }
                        }
                    }
                }
            } else {
                Section("已打开的项目") {
                    if knownDirs.isEmpty {
                        Text("暂无项目目录")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.secondaryText)
                    }
                    ForEach(knownDirs) { e in
                        Button {
                            onPick(e.path)
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundColor(Theme.accent)
                                Text(e.path)
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.primaryText)
                                    .lineLimit(1)
                                Spacer()
                                if e.browsable {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11))
                                        .foregroundColor(Theme.secondaryText)
                                }
                            }
                        }
                    }
                }
                if conn.apiVersion >= 2 {
                    Section {
                        Button {
                            Task { await browse("") }
                        } label: {
                            Label("浏览服务器目录…", systemImage: "externaldrive")
                                .foregroundColor(Theme.accent)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.pageBackground)
    }

    private func load() async {
        loading = true
        errorMsg = ""
        let client = ApiClient(conn: conn)
        do {
            knownDirs = try await client.listKnownDirs()
        } catch {
            errorMsg = (error as? ApiError)?.message ?? "\(error)"
        }
        loading = false
    }

    private func browse(_ dir: String) async {
        loading = true
        let client = ApiClient(conn: conn)
        do {
            var target = dir
            if target.isEmpty {
                target = (try? await client.currentDirectory()) ?? ""
            }
            subDirs = try await client.listSubDirs(target)
            browseDir = target
        } catch {
            errorMsg = (error as? ApiError)?.message ?? "\(error)"
        }
        loading = false
    }
}
