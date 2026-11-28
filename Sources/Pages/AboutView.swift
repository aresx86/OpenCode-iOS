import SwiftUI
import UIKit

private struct VersionEntry: Identifiable {
    let id: String
    let date: String
    let changes: [String]

    init(_ version: String, _ date: String, _ changes: [String]) {
        self.id = version
        self.date = date
        self.changes = changes
    }
}

struct AboutView: View {
    private let history: [VersionEntry] = [
        VersionEntry("0.2.0", "2026-11-28", [
            "新增「关于」页面，显示版本号与更新日志",
            "适配 opencode V2 服务端：消息列表、SSE 事件流、提示接口全面兼容",
            "修复旧对话发送消息后看不到 AI 回复的问题（V2 消息顺序为最新在前）",
            "修复服务端升级 V2 后仍显示 V1、旧会话不显示、新建会话 405 的问题",
            "语音输入（中文识别）、图片 / 文件附件、应用图标与鸿蒙版一致"
        ]),
        VersionEntry("0.1.0", "2026-11-27", [
            "首个版本（移植自鸿蒙版）：连接管理、多连接切换",
            "会话列表分组、搜索、重命名与删除",
            "聊天对话、流式回复、权限审批、工具调用卡片与 Diff 渲染",
            "Agent / 模型切换、Markdown 渲染"
        ])
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 6) {
                    if let icon = UIImage(named: "AppIcon") {
                        Image(uiImage: icon)
                            .resizable()
                            .frame(width: 84, height: 84)
                            .cornerRadius(20)
                            .padding(.bottom, 8)
                    }
                    Text("OpenCode")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Theme.primaryText)
                    Text(versionLabel)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 24)

                Text("更新日志")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)

                ForEach(history) { entry in
                    versionCard(entry)
                }

                Text("OpenCode iOS 客户端 · 连接自建 opencode 服务器")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 16)
        }
        .background(Theme.pageBackground)
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.pageBackground, for: .navigationBar)
    }

    private var versionLabel: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let code = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        if v.isEmpty { return "iOS 客户端" }
        return "v\(v)" + (code.isEmpty ? "" : "（\(code)）")
    }

    private func versionCard(_ entry: VersionEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("v" + entry.id)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Theme.accent)
                Spacer()
                Text(entry.date)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
            }
            .padding(.bottom, 10)

            ForEach(entry.changes, id: \.self) { change in
                HStack(alignment: .top, spacing: 8) {
                    Text("·")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondaryText)
                    Text(change)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.primaryText)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.bottom, 6)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
        .padding(.bottom, 4)
    }
}
