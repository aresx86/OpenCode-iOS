import Foundation

// MARK: - JSON helpers (port of getStr/getNum/getBool/getObj/getArr)

func jRoot(_ text: String) -> Any? {
    guard let data = text.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: data)
}

func jDict(_ o: Any?) -> [String: Any]? {
    o as? [String: Any]
}

func jArr(_ o: Any?) -> [Any] {
    o as? [Any] ?? []
}

func jStr(_ o: Any?, _ key: String, _ fallback: String = "") -> String {
    guard let d = o as? [String: Any] else { return fallback }
    return d[key] as? String ?? fallback
}

func jNum(_ o: Any?, _ key: String, _ fallback: Double = 0) -> Double {
    guard let d = o as? [String: Any] else { return fallback }
    if let n = d[key] as? NSNumber { return n.doubleValue }
    if let s = d[key] as? String, let v = Double(s) { return v }
    return fallback
}

func jBool(_ o: Any?, _ key: String, _ fallback: Bool = false) -> Bool {
    guard let d = o as? [String: Any] else { return fallback }
    return d[key] as? Bool ?? fallback
}

func jObj(_ o: Any?, _ key: String) -> [String: Any]? {
    guard let d = o as? [String: Any], let v = d[key] else { return nil }
    return v as? [String: Any]
}

func jArr(_ o: Any?, _ key: String) -> [Any] {
    guard let d = o as? [String: Any] else { return [] }
    return d[key] as? [Any] ?? []
}

func topArray(_ root: Any?) -> [Any] {
    if let arr = root as? [Any] { return arr }
    if let d = root as? [String: Any] { return d["data"] as? [Any] ?? [] }
    return []
}

// MARK: - Types

struct SessionTime {
    var created: Double
    var updated: Double
    var busy: Double?
    var idle: Double?
}

struct SessionInfo {
    var id: String
    var title: String?
    var projectID: String?
    var parentID: String?
    var directory: String?
    var files: Int?
    var agent: String?
    var model: String?
    var modelProvider: String?
    var time: SessionTime?
}

struct AgentOption: Identifiable {
    var id: String
    var name: String
    var description: String
    var mode: String
    var hidden: Bool
}

struct ModelOption: Identifiable, Hashable {
    var id: String
    var providerID: String
    var name: String
}

struct PermissionRequest: Identifiable {
    var id: String
    var sessionID: String?
    var action: String?
    var message: String?
    var resources: [String]?
}

final class ChatItem: Identifiable {
    var key: String
    var role = "assistant"
    var text = ""
    var reasoning = ""
    var toolName = ""
    var toolState = ""
    var toolOutput = ""
    var filePath = ""
    var commandText = ""
    var diffOld = ""
    var diffNew = ""
    var diffPatch = ""
    var fileMime = ""
    var fileUrl = ""
    var fileName = ""
    var created: Double = 0

    init(key: String) { self.key = key }
    var id: String { key }
    var isUser: Bool { role == "user" }
    var isTool: Bool { role == "tool" }
    var isFile: Bool { !fileUrl.isEmpty }
}

struct PendingAttachment {
    var name: String
    var mime: String
    var dataUrl: String
    var isImage: Bool
}

final class Connection: Codable {
    var id = ""
    var name = ""
    var baseUrl = ""
    var username = ""
    var password = ""
    var apiVersion = 0
    var serverVersion = ""

    var displayName: String { name.isEmpty ? trimSlash(baseUrl) : name }
}

struct FsEntry: Identifiable {
    var path: String
    var name: String
    var isDir: Bool
    var browsable: Bool
    var id: String { path }
}

struct SessionGroup: Identifiable {
    var directory: String
    var shortName: String
    var count: Int
    var sessions: [SessionInfo]
    var id: String { directory }
}

// MARK: - URL / path utils

func trimSlash(_ url: String) -> String {
    var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
    while let last = u.last, last == "/" || last == "\\" {
        u.removeLast()
    }
    return u
}

func shortNameOf(_ dir: String) -> String {
    if dir.isEmpty { return "" }
    let all = dir.split(whereSeparator: { $0 == "/" || $0 == "\\" }).map(String.init)
    return all.last ?? ""
}

func joinPath(_ dir: String, _ rel: String) -> String {
    if dir.isEmpty { return rel }
    let base = dir.hasSuffix("/") || dir.hasSuffix("\\") ? dir : dir + "/"
    return base + rel
}

func parentOf(_ dir: String) -> String {
    if dir.isEmpty { return "" }
    let norm = dir.replacingOccurrences(of: "\\", with: "/")
    if norm == "/" || (norm.count <= 3 && norm.count > 1 && norm[norm.index(after: norm.startIndex)] == ":") {
        return dir
    }
    guard let idx = norm.lastIndex(of: "/") else { return dir }
    if idx == norm.startIndex { return "/" }
    var parent = String(norm[..<idx])
    if parent.count == 2 && parent[parent.index(after: parent.startIndex)] == ":" {
        parent += "/"
    }
    return parent
}

// MARK: - Session parsing

func sessionFrom(_ o: Any?) -> SessionInfo {
    var s = SessionInfo(id: jStr(o, "id"))
    let t = jStr(o, "title")
    if !t.isEmpty { s.title = t }
    let pid = jStr(o, "projectID")
    if !pid.isEmpty { s.projectID = pid }
    let parent = jStr(o, "parentID")
    if !parent.isEmpty { s.parentID = parent }
    var dir = jStr(o, "directory")
    if dir.isEmpty, let loc = jObj(o, "location") {
        dir = jStr(loc, "directory")
    }
    if !dir.isEmpty { s.directory = dir }
    if let summary = jObj(o, "summary") {
        let files = Int(jNum(summary, "files"))
        if files > 0 { s.files = files }
    }
    let agent = jStr(o, "agent")
    if !agent.isEmpty { s.agent = agent }
    if let modelObj = jObj(o, "model") {
        let mid = jStr(modelObj, "id", jStr(modelObj, "modelID"))
        if !mid.isEmpty { s.model = mid }
        let mp = jStr(modelObj, "providerID", jStr(modelObj, "canonical"))
        if !mp.isEmpty { s.modelProvider = mp }
    }
    if let tm = jObj(o, "time") {
        var t = SessionTime(created: jNum(tm, "created"), updated: jNum(tm, "updated", jNum(tm, "created")))
        let busy = jNum(tm, "busy")
        if busy > 0 { t.busy = busy }
        let idle = jNum(tm, "idle")
        if idle > 0 { t.idle = idle }
        s.time = t
    }
    return s
}

func isSessionBusy(_ s: SessionInfo) -> Bool {
    guard let t = s.time else { return false }
    let busy = t.busy ?? 0
    let idle = t.idle ?? 0
    return busy > 0 && busy >= idle
}

func agentColorHex(_ name: String) -> String {
    if name == "plan" { return "#A78BFA" }
    if name == "general" { return "#4ADE80" }
    if name.isEmpty || name == "build" { return "#4CC9F0" }
    return "#4ADE80"
}

func parseSessionObject(_ text: String) -> SessionInfo? {
    guard let obj = jRoot(text) else { return nil }
    let inner = jObj(obj, "data")
    var target: Any? = obj
    if let inner {
        target = inner
    }
    let s = sessionFrom(target)
    return s.id.isEmpty ? nil : s
}

func parseSessions(_ text: String) -> [SessionInfo] {
    var result: [SessionInfo] = []
    for o in topArray(jRoot(text)) {
        let s = sessionFrom(o)
        if !s.id.isEmpty { result.append(s) }
    }
    result.sort { ($0.time?.updated ?? 0) > ($1.time?.updated ?? 0) }
    return result
}

func parseActiveSessions(_ text: String) -> [String] {
    guard let root = jRoot(text), let rootDict = root as? [String: Any] else { return [] }
    let data = rootDict["data"] as? [String: Any]
    let target = data ?? rootDict
    var out: [String] = []
    for (k, v) in target {
        if jStr(v, "type") == "idle" { continue }
        out.append(k)
    }
    return out
}

// MARK: - Agents / models

func parseAgents(_ text: String) -> [AgentOption] {
    var result: [AgentOption] = []
    for o in topArray(jRoot(text)) {
        let id = jStr(o, "id", jStr(o, "name"))
        if id.isEmpty { continue }
        result.append(AgentOption(
            id: id,
            name: jStr(o, "name", id),
            description: jStr(o, "description"),
            mode: jStr(o, "mode"),
            hidden: jBool(o, "hidden")
        ))
    }
    return result
}

func parseModels(_ text: String) -> [ModelOption] {
    var result: [ModelOption] = []
    guard let root = jRoot(text) else { return result }
    if let arr = root as? [Any] {
        for o in arr {
            let id = jStr(o, "id", jStr(o, "modelID"))
            if id.isEmpty { continue }
            result.append(ModelOption(id: id, providerID: jStr(o, "providerID", jStr(o, "canonical")), name: jStr(o, "name", id)))
        }
        return result
    }
    guard let d = root as? [String: Any] else { return result }
    var arr = d["data"] as? [Any] ?? []
    if arr.isEmpty {
        let providers = d["providers"] as? [Any] ?? []
        for p in providers {
            let pid = jStr(p, "id", jStr(p, "providerID"))
            guard let models = jObj(p, "models") else { continue }
            for (k, m) in models {
                let id = jStr(m, "id", k)
                result.append(ModelOption(id: id, providerID: pid, name: jStr(m, "name", id)))
            }
        }
        return result
    }
    for o in arr {
        let id = jStr(o, "id", jStr(o, "modelID"))
        if id.isEmpty { continue }
        result.append(ModelOption(id: id, providerID: jStr(o, "providerID", jStr(o, "canonical")), name: jStr(o, "name", id)))
    }
    return result
}

// MARK: - FS / directory parsing

func parseFsEntries(_ text: String) -> [FsEntry] {
    var out: [FsEntry] = []
    let root = jRoot(text)
    let arr: [Any]
    if let a = root as? [Any] {
        arr = a
    } else {
        arr = jArr(root, "data")
    }
    for it in arr {
        let type = jStr(it, "type")
        if !type.isEmpty && type != "directory" { continue }
        let p = jStr(it, "path")
        if p.isEmpty || p == "." || p == ".." { continue }
        let sn = shortNameOf(p)
        out.append(FsEntry(path: p, name: sn.isEmpty ? p : sn, isDir: true, browsable: true))
    }
    out.sort { $0.name.lowercased() < $1.name.lowercased() }
    return out
}

func parseProjectDirs(_ text: String) -> [FsEntry] {
    var out: [FsEntry] = []
    let root = jRoot(text)
    let arr: [Any]
    if let a = root as? [Any] {
        arr = a
    } else {
        arr = jArr(root, "data")
    }
    for it in arr {
        var dir = jStr(it, "worktree")
        if dir.isEmpty { dir = jStr(it, "directory") }
        if dir.isEmpty { continue }
        if out.contains(where: { $0.path == dir }) { continue }
        let sn = shortNameOf(dir)
        out.append(FsEntry(path: dir, name: sn.isEmpty ? dir : sn, isDir: true, browsable: false))
    }
    return out
}

func parseDirFromLocation(_ text: String) -> String {
    guard let root = jRoot(text) as? [String: Any] else { return "" }
    for key in ["directory", "absolute", "worktree", "current"] {
        let v = root[key] as? String ?? ""
        if !v.isEmpty { return v }
    }
    return ""
}

func groupSessions(_ sessions: [SessionInfo]) -> [SessionGroup] {
    var groups: [SessionGroup] = []
    for s in sessions {
        let dir = s.directory ?? ""
        if let idx = groups.firstIndex(where: { $0.directory == dir }) {
            groups[idx].sessions.append(s)
            groups[idx].count = groups[idx].sessions.count
        } else {
            groups.append(SessionGroup(
                directory: dir,
                shortName: dir.isEmpty ? "默认目录" : shortNameOf(dir),
                count: 1,
                sessions: [s]
            ))
        }
    }
    return groups
}

// MARK: - Chat parsing

private func partToToolItem(_ p: Any, _ msgKey: String, _ idx: Int) -> ChatItem {
    let item = ChatItem(key: msgKey + "#tool" + String(idx))
    item.role = "tool"
    item.toolName = jStr(p, "name", jStr(p, "tool", "tool"))
    let st = jObj(p, "state")
    var status = jStr(st, "status")
    if status.isEmpty { status = jStr(p, "status") }
    item.toolState = status
    var out = jStr(st, "output")
    if out.isEmpty { out = jStr(st, "error") }
    if out.isEmpty { out = jStr(p, "error") }
    item.toolOutput = out
    var input = jObj(st, "input")
    if input == nil { input = jObj(p, "input") }
    if let input = input {
        let tool = item.toolName
        let fp = jStr(input, "filePath", jStr(input, "path"))
        if tool == "edit" {
            item.filePath = fp
            item.diffOld = jStr(input, "oldString")
            item.diffNew = jStr(input, "newString")
        } else if tool == "write" {
            item.filePath = fp
            item.diffNew = jStr(input, "content")
        } else if tool == "patch" {
            item.filePath = fp
            item.diffPatch = jStr(input, "diff")
        } else if tool == "bash" {
            item.commandText = jStr(input, "command")
        } else {
            item.filePath = jStr(input, "filePath", jStr(input, "path", jStr(input, "pattern")))
        }
    }
    return item
}

func parseChatItems(_ text: String) -> [ChatItem] {
    var out: [ChatItem] = []
    let root = jRoot(text)
    var arr = topArray(root)
    if arr.isEmpty, let d = root as? [String: Any] {
        arr = d["data"] as? [Any] ?? []
    }
    for (i, entry) in arr.enumerated() {
        var role = ""
        var msgId = ""
        var created: Double = 0
        var parts: [Any] = []
        var directText = ""
        if let info = jObj(entry, "info") {
            role = jStr(info, "role")
            msgId = jStr(info, "id")
            if let tm = jObj(info, "time") {
                created = jNum(tm, "created")
            }
            parts = jArr(entry, "parts")
        } else {
            role = jStr(entry, "role")
            if role.isEmpty { role = jStr(entry, "type") }
            msgId = jStr(entry, "id")
            if let tm = jObj(entry, "time") {
                created = jNum(tm, "created")
            }
            parts = jArr(entry, "parts")
            if parts.isEmpty { parts = jArr(entry, "content") }
            let t = jStr(entry, "text")
            if !t.isEmpty { directText = t }
        }
        if role.isEmpty { role = "assistant" }
        var texts = ""
        var reasoning = ""
        var toolIdx = 0
        var fileItems: [ChatItem] = []
        if !directText.isEmpty && (role == "user" || parts.isEmpty) {
            texts = directText
        }
        for (j, p) in parts.enumerated() {
            let ptype = jStr(p, "type")
            if ptype == "text" {
                let t = jStr(p, "text")
                if !t.isEmpty {
                    if !texts.isEmpty { texts += "\n\n" }
                    texts += t
                }
            } else if ptype == "reasoning" || ptype == "thinking" {
                let t = jStr(p, "text")
                if !t.isEmpty {
                    if !reasoning.isEmpty { reasoning += "\n" }
                    reasoning += t
                }
            } else if ptype == "tool" {
                out.append(partToToolItem(p, msgId.isEmpty ? "m" + String(i) : msgId, toolIdx))
                toolIdx += 1
            } else if ptype == "file" {
                let url = jStr(p, "url")
                if url.hasPrefix("data:") {
                    let fitem = ChatItem(key: (msgId.isEmpty ? "m" + String(i) : msgId) + "#file" + String(j))
                    fitem.role = role
                    fitem.fileMime = jStr(p, "mime")
                    fitem.fileUrl = url
                    fitem.fileName = jStr(p, "filename")
                    fitem.created = created
                    fileItems.append(fitem)
                }
            }
        }
        if !texts.isEmpty || !reasoning.isEmpty {
            let item = ChatItem(key: (msgId.isEmpty ? "m" + String(i) : msgId) + "#msg")
            item.role = role
            item.text = texts
            item.reasoning = reasoning
            item.created = created
            out.append(item)
        }
        out.append(contentsOf: fileItems)
    }
    return out
}

// MARK: - Permissions

func parsePermissions(_ text: String) -> [PermissionRequest] {
    var result: [PermissionRequest] = []
    for o in topArray(jRoot(text)) {
        let id = jStr(o, "id")
        if id.isEmpty { continue }
        var p = PermissionRequest(id: id)
        let sess = jStr(o, "sessionID")
        if !sess.isEmpty { p.sessionID = sess }
        let action = jStr(o, "action")
        if !action.isEmpty { p.action = action }
        let msg = jStr(o, "message")
        if !msg.isEmpty { p.message = msg }
        let names = jArr(o, "resources").compactMap { $0 as? String }
        if !names.isEmpty { p.resources = names }
        result.append(p)
    }
    return result
}

// MARK: - System injected blocks

private func removeTagBlocks(_ text: String, _ tag: String) -> String {
    let open = "<" + tag + ">"
    let close = "</" + tag + ">"
    var out = ""
    var rest = text
    while true {
        guard let i = rest.range(of: open) else {
            out += rest
            break
        }
        let searchStart = i.upperBound
        guard let j = rest.range(of: close, range: searchStart..<rest.endIndex) else {
            out += String(rest[..<i.lowerBound])
            break
        }
        out += String(rest[..<i.lowerBound])
        rest = String(rest[j.upperBound...])
    }
    return out
}

private func removeGenericHindsight(_ text: String) -> String {
    var out = ""
    var rest = text
    while true {
        guard let i = rest.range(of: "<hindsight_") else {
            out += rest
            break
        }
        guard let gt = rest.range(of: ">", range: i.lowerBound..<rest.endIndex) else {
            out += String(rest[..<i.lowerBound])
            break
        }
        let tag = String(rest[i.upperBound..<gt.lowerBound])
        let close = "</" + tag + ">"
        guard let j = rest.range(of: close, range: gt.upperBound..<rest.endIndex) else {
            out += String(rest[..<i.lowerBound])
            break
        }
        out += String(rest[..<i.lowerBound])
        rest = String(rest[j.upperBound...])
    }
    return out
}

func stripSystemInjected(_ text: String) -> String {
    if text.isEmpty { return "" }
    var s = text
    s = removeTagBlocks(s, "hindsight_page_refresh")
    s = removeTagBlocks(s, "hindsight_pages")
    s = removeTagBlocks(s, "hindsight_memory")
    s = removeTagBlocks(s, "system-reminder")
    s = removeTagBlocks(s, "system_warning")
    s = removeTagBlocks(s, "env")
    s = removeGenericHindsight(s)
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

func countSystemInjected(_ text: String) -> Int {
    var count = 0
    let tags = ["<hindsight_page_refresh>", "<hindsight_pages>", "<hindsight_memory>", "<system-reminder>", "<system_warning>", "<env>"]
    for t in tags {
        var searchRange = text.startIndex..<text.endIndex
        while let found = text.range(of: t, range: searchRange) {
            count += 1
            searchRange = found.upperBound..<text.endIndex
        }
    }
    return count
}

func displayTitle(_ s: SessionInfo) -> String {
    guard let t = s.title, !t.isEmpty else { return "未命名会话" }
    let cleaned = stripSystemInjected(t)
    return cleaned.isEmpty ? "未命名会话" : cleaned
}

func isSystemInjected(_ item: ChatItem) -> Bool {
    let t = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.hasPrefix("<hindsight_") || t.hasPrefix("<system-reminder>")
        || t.hasPrefix("<system_warning>") || t.hasPrefix("<env>")
}

// MARK: - Time formatting

func formatTime(_ ms: Double) -> String {
    if ms <= 0 { return "" }
    let d = Date(timeIntervalSince1970: ms / 1000.0)
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.string(from: d)
}

func formatRelative(_ ms: Double) -> String {
    if ms <= 0 { return "" }
    let diff = Date().timeIntervalSince1970 * 1000 - ms
    if diff < 60 * 1000 { return "刚刚" }
    if diff < 3600 * 1000 { return "\(Int(diff / 60000)) 分钟前" }
    if diff < 24 * 3600 * 1000 { return "\(Int(diff / 3600000)) 小时前" }
    if diff < 7 * 24 * 3600 * 1000 { return "\(Int(diff / 86400000)) 天前" }
    return formatTime(ms)
}
