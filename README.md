# OpenCode iOS

iPhone 原生（SwiftUI）的 [opencode](https://github.com/anomalyco/opencode) 客户端，[OpenCode-HarmonyOS](https://github.com/aresx86/OpenCode-HarmonyOS) 的 iOS 移植版。连接你自己运行的 opencode 服务器，在手机上查看会话、发送任务、审批工具调用。

> 与 opencode 官方无隶属关系，独立社区客户端，通过 opencode 开放 HTTP API 通信。

当前状态（M3 功能齐平鸿蒙版）：

已实现：

- 多连接管理（添加 / 编辑 / 重命名 / 删除 / 测试连通性，自动识别 opencode V1 / V2 API）
- 会话列表（按项目目录分组、搜索、相对时间、运行中标识、下拉刷新、滑动删除、重命名）
- 新建会话选目录（V1 列出已打开项目，V2 支持逐级浏览服务器目录树）
- **流式对话**（SSE 实时输出、发送消息、乐观上屏、断线自动重连、5s 轮询兜底、执行中状态恢复）
- **权限审批**（AI 请求敏感操作时直接「拒绝 / 本次允许 / 总是允许」）
- **中断执行**（一键停止）
- **Agent / 模型切换**（智能体选择、按供应商分组的模型搜索选择，V1 提示下次发送生效）
- Markdown 渲染（标题 / 列表 / 引用 / 行内代码 / 代码块带复制 / 链接）
- 工具调用卡片（运行状态、命令与文件路径、展开查看输出）
- Diff 视图（edit / write LCS 行级差异、patch 解析、增删行统计、一键复制）
- **语音输入**（SFSpeechRecognizer 中文识别，复用现有输入作前缀、3 秒静音自动结束、60 秒上限）
- **图片 / 文件附件**（相册多选 + 文件导入，上限 6 个、单文件 15MB，缩略图可删除）
- 思考过程折叠、系统注入内容过滤（显示/隐藏切换）
- 应用图标（与鸿蒙版一致，tools/port_icon.mjs 从鸿蒙仓库 216px 图标放大重编码）
- 连接密码仅保存在本机 UserDefaults，不上传

待办：

- [ ] 真机实测反馈修复（欢迎提 issue）

## 系统要求

- iPhone：iOS 16 及以上
- 构建：macOS + Xcode（或直接用本仓库的 GitHub Actions 云构建）

## 服务端准备

与鸿蒙版完全一致：

```bash
npm install -g @opencode/cli
OPENCODE_SERVER_PASSWORD=你的密码 opencode serve --hostname 0.0.0.0 --port 4096
```

| 方式 | 说明 |
|---|---|
| 局域网 | 同一 WiFi 下直接连接 `http://电脑IP:4096` |
| Tailscale | 使用 `http://100.x.x.x:4096`，随时随地直连 |
| Cloudflare Tunnel / ngrok | 公网隧道地址 |

## 云构建 IPA（无需 Mac）

1. Push 本仓库到 GitHub（Actions 会自动在 macOS runner 上构建）
2. 打开仓库 Actions 页 → 最新 "Build unsigned IPA" → Artifacts 下载 `OpenCode-unsigned-ipa`
3. Windows 上用 [Sideloadly](https://sideloadly.io) 安装：
   - iPhone 连接电脑，Sideloadly 拖入 ipa，输入你的 Apple ID
   - 免费 Apple ID 签名 7 天有效，到期重签一次即可（最多装 3 个免费签名应用）

也可以 `workflow_dispatch` 手动触发构建。

## 本地构建（有 Mac 时）

```bash
brew install xcodegen
xcodegen generate
open OpenCode.xcodeproj
```

Xcode 中选择真机直接 Run（免费签名）。

## 项目结构

```
OpenCode-iOS/
├── project.yml                     # XcodeGen 工程定义（iOS 16.1+）
├── .github/workflows/build.yml     # CI 云构建 unsigned ipa
├── tools/port_icon.mjs             # 从鸿蒙仓库移植应用图标（解码→放大→重编码）
└── Sources/
    ├── OpenCodeApp.swift            # 入口
    ├── Theme.swift                  # 主题色（对齐鸿蒙版配色）
    ├── Model/Models.swift           # API 类型、JSON 解析、系统块剥离（移植 Models.ets）
    ├── Service/ApiClient.swift      # REST 客户端 V1+V2 双协议（移植 ApiClient.ets）
    ├── Service/EventStream.swift    # SSE 事件流（移植 EventStream.ets）
    ├── Service/VoiceInput.swift     # 语音输入（移植 VoiceInput.ets，SFSpeechRecognizer）
    ├── Store/AppState.swift         # 连接持久化与全局状态（移植 Store.ets）
    ├── Resources/Assets.xcassets    # 应用图标（与鸿蒙版一致）
    ├── View/
    │   ├── MarkdownView.swift       # Markdown 渲染（移植 Markdown.ets）
    │   └── DiffView.swift           # LCS diff / patch 视图（移植 DiffView.ets）
    └── Pages/
        ├── MainView.swift           # 底部双页签
        ├── ConnectionsView.swift    # 连接页
        ├── EditConnectionView.swift # 连接编辑/测试
        ├── SessionsView.swift       # 会话列表
        ├── DirectoryPickerView.swift# 新会话选目录
        ├── ChatState.swift          # 对话页状态与逻辑（移植 Chat.ets 逻辑层）
        └── ChatView.swift           # 对话页 UI（流式/审批/附件/语音/工具卡片/输入栏）
```

零第三方依赖（与鸿蒙版同一原则），构建仅需 XcodeGen 生成工程。

## 隐私与安全

App 不收集任何数据；对话内容仅在你手机与你的服务器之间传输；API 密钥保存在服务端，App 不经手模型密钥。避免在公网明文 HTTP 环境下传输敏感代码。

## 许可证

MIT
