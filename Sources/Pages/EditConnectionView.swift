import SwiftUI

struct EditConnectionView: View {
    let editId: String

    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var testing = false
    @State private var testText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                field("名称", text: $name, placeholder: "可选，默认使用地址")
                field("服务器地址", text: $url, placeholder: "http://192.168.1.100:4096")
                field("用户名", text: $username, placeholder: "默认 opencode")
                secureField("密码", text: $password, placeholder: "OPENCODE_SERVER_PASSWORD，可留空")

                Text("提示：电脑上运行 opencode serve --hostname 0.0.0.0 --port 4096，手机需与电脑在同一局域网")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
                    .textSelection(.enabled)

                if !testText.isEmpty {
                    Text(testText)
                        .font(.system(size: 12))
                        .foregroundColor(testText.hasPrefix("连接成功") ? Theme.accent : Theme.danger)
                }

                HStack(spacing: 12) {
                    Button {
                        test()
                    } label: {
                        Text(testing ? "测试中…" : "测试连接")
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardBackground))
                            .foregroundColor(Theme.accent)
                    }
                    .disabled(testing)

                    Button {
                        save()
                    } label: {
                        Text("保存")
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent))
                            .foregroundColor(Color(hex: "#0F172A"))
                    }
                }
                .padding(.top, 8)
            }
            .padding(16)
        }
        .background(Theme.pageBackground)
        .navigationTitle(editId.isEmpty ? "添加连接" : "编辑连接")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.pageBackground, for: .navigationBar)
        .onAppear(perform: loadExisting)
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Theme.secondaryText)
            TextField(placeholder, text: text)
                .font(.system(size: 15))
                .foregroundColor(Theme.primaryText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.inputBackground))
        }
    }

    private func secureField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Theme.secondaryText)
            SecureField(placeholder, text: text)
                .font(.system(size: 15))
                .foregroundColor(Theme.primaryText)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.inputBackground))
        }
    }

    private func loadExisting() {
        guard !editId.isEmpty, let c = ConnectionStore.shared.find(editId) else { return }
        name = c.name
        url = c.baseUrl
        username = c.username
        password = c.password
    }

    private func buildConn() -> Connection {
        let c = Connection()
        c.id = editId.isEmpty ? ConnectionStore.shared.newId() : editId
        let trimmed = trimSlash(url)
        c.name = name.isEmpty ? trimmed : name
        c.baseUrl = trimmed
        c.username = username
        c.password = password
        c.apiVersion = 0
        if !editId.isEmpty, let exist = ConnectionStore.shared.find(editId) {
            c.apiVersion = exist.apiVersion
        }
        return c
    }

    private func test() {
        if trimSlash(url).isEmpty {
            testText = "请先填写服务器地址"
            return
        }
        testing = true
        testText = ""
        let c = buildConn()
        Task {
            do {
                let v = try await ApiClient(conn: c).detect()
                testText = "连接成功 · opencode \(v) · API v\(c.apiVersion)"
            } catch {
                testText = (error as? ApiError)?.message ?? "\(error)"
            }
            testing = false
        }
    }

    private func save() {
        if trimSlash(url).isEmpty {
            app.showToast("服务器地址不能为空")
            return
        }
        ConnectionStore.shared.upsert(buildConn())
        app.reload()
        app.showToast("已保存")
        dismiss()
    }
}
