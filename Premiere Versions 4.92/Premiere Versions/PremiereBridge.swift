import Foundation
import Network
import Combine
import Security

/// Local-only experimental capability bridge. Never falls back to copying an unsaved project.
@MainActor final class PremiereBridge: ObservableObject {
    static let shared = PremiereBridge()
    @Published private(set) var status = "Plugin disconnected"
    private var listener: NWListener?
    private var peer: NWConnection?
    private var authenticated = false
    private var candidates: [ObjectIdentifier: NWConnection] = [:]
    private var token = ""
    private var preparing = false
    private var prepared = false
    private var setupFailure: String?
    private var readyPort: UInt16?
    @Published private(set) var pluginVersion: String?
    @Published private(set) var openProjects: [URL]?
    @Published private(set) var activeProject: URL?
    private var pending: (id: String, path: String, continuation: CheckedContinuation<Void, Error>)?
    private var inspection: (id: String, continuation: CheckedContinuation<URL, Error>)?
    private var inspectionTimeout: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var projectsExpiry: Task<Void, Never>?
    private let queue = DispatchQueue(label: "PremiereVersions.SaveBridge")
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { PVL(message) } }
    func start() {
        guard listener == nil else { return }
        do {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw Failure(message: "Could not prepare the Premiere plugin.") }
            token = bytes.map { String(format: "%02x", $0) }.joined()
            let options = NWProtocolWebSocket.Options()
            options.autoReplyPing = true
            options.maximumMessageSize = 8192
            let parameters = NWParameters.tcp
            parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            let server = try NWListener(using: parameters)
            server.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            server.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    if case .ready = state, let port = self.listener?.port?.rawValue { self.readyPort = port; self.preparePlugin(port) }
                    if case .failed = state { self.setupFailure = "Local bridge unavailable"; self.status = "Local bridge unavailable" }
                }
            }
            listener = server; server.start(queue: queue)
            status = "Waiting for Premiere plugin"
        } catch { status = error.localizedDescription }
    }
    private func preparePlugin(_ port: UInt16) {
        guard !preparing, !prepared else { return }; preparing = true
        Task { @MainActor in
            defer { preparing = false }
            do {
                let data = try JSONSerialization.data(withJSONObject: ["protocolVersion": 2, "port": Int(port), "credential": token])
                _ = try await PVBridgeInstallClient.install(data)
                prepared = true; setupFailure = nil
            } catch { setupFailure = error.localizedDescription; status = "Could not prepare the Premiere plugin." }
        }
    }
    private func accept(_ connection: NWConnection) {
        guard candidates.count < 4 else { connection.cancel(); return }
        let key = ObjectIdentifier(connection); candidates[key] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            Task { @MainActor in
                if case .failed = state { self?.closed(connection) }
                if case .cancelled = state { self?.closed(connection) }
            }
        }
        connection.start(queue: queue)
        receive(connection)
        Task { @MainActor [weak self, weak connection] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, let connection, self.peer !== connection else { return }
            connection.cancel(); self.candidates.removeValue(forKey: key)
        }
    }
    private func receive(_ connection: NWConnection) {
        connection.receiveMessage { [weak self, weak connection] data, context, _, error in
            guard let connection else { return }
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                if error != nil { self.closed(connection); connection.cancel(); return }
                guard let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata else {
                    self.closed(connection); connection.cancel(); return
                }
                if metadata.opcode == .ping || metadata.opcode == .pong { self.receive(connection); return }
                guard metadata.opcode == .text, let data, data.count <= 8192,
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.closed(connection); connection.cancel(); return
                }
                self.handle(object, connection)
                if self.candidates[ObjectIdentifier(connection)] != nil { self.receive(connection) }
            }
        }
    }
    private func handle(_ message: [String: Any], _ connection: NWConnection) {
        if peer !== connection {
            guard message["type"] as? String == "hello", message["protocol"] as? Int == 2,
                  message["plugin"] as? String == "dev.premiereversions.bridge",
                  let received = message["token"] as? String, validToken(received), peer == nil else {
                connection.cancel(); candidates.removeValue(forKey: ObjectIdentifier(connection)); return
            }
            peer = connection; authenticated = true; pluginVersion = message["version"] as? String; status = "Premiere plugin connected"
            send(["type":"welcome", "protocol":2, "language": UserDefaults.standard.string(forKey: "interfaceLanguage") == "ru" ? "ru" : "en"], connection); return
        }
        if message["type"] as? String == "open-window" { NotificationCenter.default.post(name: Notification.Name("PVPremierePanelOpen"), object: nil); return }
        if message["type"] as? String == "projects-unavailable" { projectsExpiry?.cancel(); openProjects = nil; activeProject = nil; return }
        if message["type"] as? String == "projects" {
            guard let payload = message["data"] as? [String: Any],
                  let paths = payload["projects"] as? [String], paths.count <= 128,
                  let active = payload["active"] as? String,
                  paths.allSatisfy({ $0.hasPrefix("/") && $0.lowercased().hasSuffix(".prproj") && $0.utf8.count < 4096 }),
                  active.isEmpty || paths.contains(active) else { openProjects = nil; activeProject = nil; return }
            projectsExpiry?.cancel()
            projectsExpiry = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(45)) } catch { return }
                self?.openProjects = nil; self?.activeProject = nil
            }
            openProjects = paths.map { URL(fileURLWithPath: $0).standardizedFileURL }
            activeProject = active.isEmpty ? nil : URL(fileURLWithPath: active).standardizedFileURL
            return
        }
        if message["type"] as? String == "result", let request = inspection, message["id"] as? String == request.id {
            inspection = nil; inspectionTimeout?.cancel(); inspectionTimeout = nil
            if message["ok"] as? Bool == true, let path = message["path"] as? String, path.hasPrefix("/"), path.lowercased().hasSuffix(".prproj") {
                request.continuation.resume(returning: URL(fileURLWithPath: path).standardizedFileURL)
            } else { request.continuation.resume(throwing: Failure(message: message["error"] as? String ?? "No active project")) }
            return
        }
        guard message["type"] as? String == "result", let request = pending,
              message["id"] as? String == request.id else { return }
        if message["ok"] as? Bool == true, let path = message["path"] as? String,
           canonical(path) == canonical(request.path) {
            finish(nil); status = "Premiere confirmed saving"
        } else {
            finish(Failure(message: message["error"] as? String ?? "Plugin did not confirm the selected project"))
        }
    }
    private func validToken(_ received: String) -> Bool {
        let lhs = Array(received.utf8), rhs = Array(token.utf8)
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
    private func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping
    }
    private func send(_ object: [String: Any], _ connection: NWConnection) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "pv-test", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { [weak self, weak connection] error in
            if error != nil, let connection { Task { @MainActor in self?.closed(connection) } }
        })
    }
    func languageChanged() {
        guard let peer, authenticated else { return }
        send(["type":"language", "language": UserDefaults.standard.string(forKey: "interfaceLanguage") == "ru" ? "ru" : "en"], peer)
    }
    func inspectActiveProject() async throws -> URL {
        guard let connection = peer, authenticated else { throw Failure(message: "Premiere plugin disconnected") }
        guard inspection == nil, pending == nil else { throw Failure(message: "A Premiere request is already in progress") }
        let id = UUID().uuidString
        return try await withCheckedThrowingContinuation { continuation in
            inspection = (id, continuation)
            inspectionTimeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard let self, let request = self.inspection, request.id == id else { return }
                self.inspection = nil; request.continuation.resume(throwing: Failure(message: "Premiere did not respond"))
            }
            send(["type":"request", "id":id, "op":"inspect"], connection)
        }
    }
    func save(_ source: URL) async throws {
        start()
        for _ in 0..<200 {
            if prepared || setupFailure != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        if let setupFailure { throw Failure(message: setupFailure) }
        guard prepared else { throw Failure(message: "Could not prepare the Premiere plugin.") }
        for _ in 0..<100 {
            if peer != nil && authenticated { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard let connection = peer, authenticated else {
            throw Failure(message: "Restart Premiere Pro to connect the save plugin, then try again.")
        }
        guard pending == nil && inspection == nil else { throw Failure(message: "A Premiere save is already in progress") }
        let id = UUID().uuidString
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                pending = (id, source.path, continuation)
                status = "Waiting for Premiere to save…"
                timeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(120)) } catch { return }
                    guard self?.pending?.id == id else { return }
                    self?.finish(Failure(message: "Premiere save timed out; no archive copy created"))
                }
                send(["type":"request", "id":id, "op":"save", "expectedPath":source.path], connection)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.pending?.id == id else { return }
                self?.finish(CancellationError())
            }
        }
    }

    private func closed(_ connection: NWConnection) {
        candidates.removeValue(forKey: ObjectIdentifier(connection))
        if peer === connection {
            projectsExpiry?.cancel(); projectsExpiry = nil
            inspectionTimeout?.cancel(); inspectionTimeout = nil
            if let request = inspection { inspection = nil; request.continuation.resume(throwing: Failure(message: "Premiere plugin disconnected")) }
            peer = nil; authenticated = false; openProjects = nil; activeProject = nil; status = "Premiere plugin disconnected"
            finish(Failure(message: "Plugin disconnected; no archive copy created"))
        }
    }
    private func finish(_ error: Error?) {
        timeout?.cancel(); timeout = nil
        guard let request = pending else { return }; pending = nil
        if let error { request.continuation.resume(throwing: error) }
        else { request.continuation.resume() }
    }
}
