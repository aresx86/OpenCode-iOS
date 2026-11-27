import Foundation

final class EventStream {
    let conn: Connection
    var onEvent: (String, String) -> Void = { _, _ in }
    var onClosed: () -> Void = {}
    var onStarted: () -> Void = {}
    private var task: Task<Void, Never>?

    init(conn: Connection) {
        self.conn = conn
    }

    func start() {
        let path = conn.apiVersion == 1 ? "/event" : "/api/event"
        guard let url = URL(string: trimSlash(conn.baseUrl) + path) else {
            onClosed()
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 600
        for (k, v) in ApiClient.authHeaders(conn, accept: "text/event-stream") {
            req.setValue(v, forHTTPHeaderField: k)
        }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: req)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    await MainActor.run { self.onClosed() }
                    return
                }
                await MainActor.run { self.onStarted() }
                var event = ""
                var data = ""
                for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    if line.isEmpty {
                        if !event.isEmpty {
                            await MainActor.run { self.onEvent(event, data) }
                        }
                        event = ""
                        data = ""
                    } else if line.hasPrefix("event:") {
                        event = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                    } else if line.hasPrefix("data:") {
                        let d = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        data = data.isEmpty ? d : data + "\n" + d
                    }
                }
                await MainActor.run { self.onClosed() }
            } catch is CancellationError {
            } catch {
                await MainActor.run { self.onClosed() }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
