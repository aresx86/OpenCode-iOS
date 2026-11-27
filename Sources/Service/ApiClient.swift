import Foundation

struct ApiError: Error, LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

final class ApiClient {
    private let conn: Connection
    var selectedAgent = ""
    var selectedModelId = ""
    var selectedModelProvider = ""

    init(conn: Connection) {
        self.conn = conn
    }

    var apiVersion: Int { conn.apiVersion }

    static func authHeaders(_ conn: Connection, accept: String) -> [String: String] {
        var h = ["Accept": accept]
        if !conn.password.isEmpty {
            let user = conn.username.isEmpty ? "opencode" : conn.username
            let token = Data("\(user):\(conn.password)".utf8).base64EncodedString()
            h["Authorization"] = "Basic \(token)"
        }
        return h
    }

    @discardableResult
    private func request(_ method: String, _ path: String, body: String = "") async throws -> String {
        let full = trimSlash(conn.baseUrl) + path
        guard let url = URL(string: full) else {
            throw ApiError(status: 0, message: "无效地址：\(full)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 300
        for (k, v) in Self.authHeaders(conn, accept: "application/json, text/event-stream") {
            req.setValue(v, forHTTPHeaderField: k)
        }
        if !body.isEmpty {
            req.httpBody = Data(body.utf8)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw ApiError(status: 0, message: "网络错误：\(error.localizedDescription)")
        }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(status) else {
            throw ApiError(status: status, message: "HTTP \(status): \(String(text.prefix(200)))")
        }
        return text
    }

    // MARK: - Detection

    @discardableResult
    func detect() async throws -> String {
        do {
            let raw = try await request("GET", "/api/info")
            let version = jStr(jRoot(raw), "version")
            conn.apiVersion = 2
            conn.serverVersion = version
            return version
        } catch let e as ApiError {
            if e.status == 401 || e.status == 403 {
                conn.apiVersion = 2
                conn.serverVersion = "需鉴权"
                return "需鉴权"
            }
        }
        do {
            let raw = try await request("GET", "/global/health")
            let version = jStr(jRoot(raw), "version")
            conn.apiVersion = 1
            conn.serverVersion = version
            return version
        } catch let e as ApiError {
            if e.status == 401 || e.status == 403 {
                conn.apiVersion = 1
                conn.serverVersion = "需鉴权"
                return "需鉴权"
            }
        }
        throw ApiError(status: 0, message: "无法连接服务器，请检查地址、网络或密码")
    }

    private func ensureDetected() async throws {
        if conn.apiVersion != 0 {
            if conn.serverVersion.isEmpty {
                await refreshVersion()
            }
            return
        }
        _ = try await detect()
    }

    private func refreshVersion() async {
        let path = conn.apiVersion == 1 ? "/global/health" : "/api/info"
        if let raw = try? await request("GET", path) {
            conn.serverVersion = jStr(jRoot(raw), "version")
        }
    }

    // MARK: - Sessions

    func listSessions() async throws -> [SessionInfo] {
        try await ensureDetected()
        var raw = ""
        if conn.apiVersion == 1 {
            do {
                raw = try await request("GET", "/experimental/session")
            } catch {
                raw = try await request("GET", "/session?roots=true&limit=50")
            }
        } else {
            raw = try await request("GET", "/api/session?limit=500&order=desc")
        }
        let all = parseSessions(raw)
        return all.filter { ($0.parentID ?? "").isEmpty }
    }

    func createSession(title: String, directory: String = "") async throws -> SessionInfo {
        try await ensureDetected()
        let path: String
        let body: String
        if conn.apiVersion == 1 {
            path = "/session"
            var obj: [String: Any] = [:]
            if !title.isEmpty { obj["title"] = title }
            if !directory.isEmpty { obj["directory"] = directory }
            body = serialize(obj)
        } else {
            path = "/api/session"
            var obj: [String: Any] = [:]
            if !directory.isEmpty {
                obj["location"] = ["directory": directory]
            }
            body = serialize(obj)
        }
        let raw = try await request("POST", path, body: body)
        let list = parseSessions(raw)
        if let first = list.first {
            return first
        }
        let obj = jRoot(raw)
        let inner = jObj(obj, "data")
        let target: Any? = inner != nil ? inner : obj
        let id = jStr(target, "id")
        if !id.isEmpty {
            var s = SessionInfo(id: id)
            let t = jStr(target, "title")
            if !t.isEmpty { s.title = t }
            return s
        }
        throw ApiError(status: -1, message: "创建会话失败：服务器返回异常")
    }

    func currentDirectory() async throws -> String {
        try await ensureDetected()
        let path = conn.apiVersion == 1 ? "/path" : "/api/location"
        let raw = try await request("GET", path)
        return parseDirFromLocation(raw)
    }

    func listSubDirs(_ dir: String) async throws -> [FsEntry] {
        try await ensureDetected()
        var query = ""
        if !dir.isEmpty {
            query = "?location%5Bdirectory%5D=" + encode(dir)
        }
        let raw = try await request("GET", "/api/fs/list" + query)
        let rel = parseFsEntries(raw)
        return rel.map { e in
            FsEntry(path: joinPath(dir, e.path), name: e.name, isDir: true, browsable: true)
        }
    }

    func listKnownDirs() async throws -> [FsEntry] {
        try await ensureDetected()
        let path = conn.apiVersion == 1 ? "/project" : "/api/session?limit=500&order=desc"
        let raw = try await request("GET", path)
        return parseProjectDirs(raw)
    }

    // MARK: - Agents / models

    func listAgents() async throws -> [AgentOption] {
        try await ensureDetected()
        let path = conn.apiVersion == 1 ? "/agent" : "/api/agent"
        let raw = try await request("GET", path)
        return parseAgents(raw)
    }

    func listModels() async throws -> [ModelOption] {
        try await ensureDetected()
        if conn.apiVersion == 1 {
            let raw = try await request("GET", "/config/providers")
            return parseModels(raw)
        }
        let raw = try await request("GET", "/api/model")
        return parseModels(raw)
    }

    func switchAgent(sessionId: String, agentId: String) async throws {
        try await ensureDetected()
        selectedAgent = agentId
        if conn.apiVersion == 1 { return }
        let body = serialize(["agent": agentId])
        do {
            _ = try await request("POST", "/api/session/\(sessionId)/agent", body: body)
        } catch let e as ApiError {
            throw e
        } catch {
            throw ApiError(status: -1, message: "\(error)")
        }
    }

    func switchModel(sessionId: String, modelId: String, providerId: String) async throws {
        try await ensureDetected()
        selectedModelId = modelId
        selectedModelProvider = providerId
        if conn.apiVersion == 1 { return }
        let body = serialize(["model": ["id": modelId, "providerID": providerId]])
        do {
            _ = try await request("POST", "/api/session/\(sessionId)/model", body: body)
        } catch let e as ApiError {
            throw e
        } catch {
            throw ApiError(status: -1, message: "\(error)")
        }
    }

    // MARK: - Session ops

    func getSession(sessionId: String) async throws -> SessionInfo {
        try await ensureDetected()
        let path = conn.apiVersion == 1 ? "/session/\(sessionId)" : "/api/session/\(sessionId)"
        let raw = try await request("GET", path)
        guard let s = parseSessionObject(raw) else {
            throw ApiError(status: -1, message: "获取会话信息失败")
        }
        return s
    }

    func listActiveSessions() async throws -> [String] {
        try await ensureDetected()
        let path = conn.apiVersion == 1 ? "/session/status" : "/api/session/active"
        let raw = try await request("GET", path)
        return parseActiveSessions(raw)
    }

    func renameSession(sessionId: String, title: String) async throws {
        try await ensureDetected()
        let body = serialize(["title": title])
        let path = conn.apiVersion == 1 ? "/session/\(sessionId)" : "/api/session/\(sessionId)"
        _ = try await request("PATCH", path, body: body)
    }

    func deleteSession(sessionId: String) async throws {
        try await ensureDetected()
        let path = (conn.apiVersion == 1 ? "/session/" : "/api/session/") + sessionId
        _ = try await request("DELETE", path)
    }

    func listMessages(sessionId: String) async throws -> [ChatItem] {
        try await ensureDetected()
        let path = (conn.apiVersion == 1 ? "/session/" : "/api/session/") + sessionId + "/message"
        let raw = try await request("GET", path)
        return parseChatItems(raw)
    }

    func prompt(sessionId: String, text: String, attachments: [PendingAttachment] = []) async throws {
        try await ensureDetected()
        let body: String
        if conn.apiVersion == 1 {
            var parts: [[String: Any]] = []
            if !text.isEmpty {
                parts.append(["type": "text", "text": text])
            }
            for a in attachments {
                parts.append(["type": "file", "mime": a.mime, "url": a.dataUrl, "filename": a.name])
            }
            var obj: [String: Any] = ["parts": parts]
            if !selectedAgent.isEmpty {
                obj["agent"] = selectedAgent
            }
            if !selectedModelId.isEmpty && !selectedModelProvider.isEmpty {
                obj["model"] = ["providerID": selectedModelProvider, "modelID": selectedModelId]
            }
            body = serialize(obj)
        } else {
            var obj: [String: Any] = ["text": text]
            if !attachments.isEmpty {
                let files: [[String: Any]] = attachments.map { a in
                    var f: [String: Any] = ["uri": a.dataUrl]
                    if !a.name.isEmpty { f["name"] = a.name }
                    return f
                }
                obj["files"] = files
            }
            body = serialize(obj)
        }
        let path = conn.apiVersion == 1
            ? "/session/\(sessionId)/message"
            : "/api/session/\(sessionId)/prompt"
        _ = try await request("POST", path, body: body)
    }

    func interrupt(sessionId: String) async throws {
        try await ensureDetected()
        let path = conn.apiVersion == 1
            ? "/session/\(sessionId)/abort"
            : "/api/session/\(sessionId)/interrupt"
        _ = try await request("POST", path)
    }

    func listPermissions(sessionId: String) async throws -> [PermissionRequest] {
        if conn.apiVersion <= 1 {
            return []
        }
        let raw = try await request("GET", "/api/session/\(sessionId)/permission")
        return parsePermissions(raw)
    }

    func replyPermission(sessionId: String, requestId: String, response: String) async throws {
        try await ensureDetected()
        if conn.apiVersion == 1 {
            let body = serialize(["response": response])
            _ = try await request("POST", "/session/\(sessionId)/permissions/\(requestId)", body: body)
        } else {
            let body = serialize(["decision": response])
            _ = try await request("POST", "/api/session/\(sessionId)/permission/\(requestId)/reply", body: body)
        }
    }

    // MARK: - Helpers

    private func serialize(_ obj: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func encode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
