import Foundation
import SwiftUI

final class ConnectionStore {
    static let shared = ConnectionStore()

    private let defaults = UserDefaults.standard
    private let listKey = "connections"
    private let showSystemKey = "show_system_blocks"

    func loadAll() -> [Connection] {
        guard let raw = defaults.string(forKey: listKey),
              let data = raw.data(using: .utf8),
              let arr = try? JSONDecoder().decode([Connection].self, from: data) else {
            return []
        }
        return arr.filter { !$0.id.isEmpty && !$0.baseUrl.isEmpty }
    }

    func saveAll(_ list: [Connection]) {
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(String(data: data, encoding: .utf8) ?? "[]", forKey: listKey)
        }
    }

    func find(_ id: String) -> Connection? {
        loadAll().first(where: { $0.id == id })
    }

    func upsert(_ c: Connection) {
        var all = loadAll()
        if let idx = all.firstIndex(where: { $0.id == c.id }) {
            all[idx] = c
        } else {
            all.append(c)
        }
        saveAll(all)
    }

    func remove(_ id: String) {
        saveAll(loadAll().filter { $0.id != id })
    }

    func newId() -> String {
        let t = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let r = String(Int.random(in: 0..<100000), radix: 36)
        return "conn_\(t)_\(r)"
    }

    var showSystem: Bool {
        get { defaults.bool(forKey: showSystemKey) }
        set { defaults.set(newValue, forKey: showSystemKey) }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var connections: [Connection] = []
    @Published var current: Connection?
    @Published var tab = 0
    @Published var sessionsTick = 0
    @Published var toast: String?

    func reload() {
        connections = ConnectionStore.shared.loadAll()
        if let cur = current, !connections.contains(where: { $0.id == cur.id }) {
            current = nil
        }
    }

    func showToast(_ message: String) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.toast == message {
                self?.toast = nil
            }
        }
    }

    func openConnection(_ c: Connection) async {
        if c.apiVersion == 0 {
            let client = ApiClient(conn: c)
            do {
                _ = try await client.detect()
                ConnectionStore.shared.upsert(c)
                reload()
            } catch {
                showToast((error as? ApiError)?.message ?? "\(error)")
                return
            }
        }
        current = c
        tab = 0
        sessionsTick += 1
    }
}
