import Foundation

@MainActor enum PVBridgeInstallClient {
    static func install(_ data: Data) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            PVBridgeInstallRequest(continuation).start(data)
        }
    }
}
@MainActor private final class PVBridgeInstallRequest {
    private var continuation: CheckedContinuation<String, Error>?
    private var connection: NSXPCConnection?
    private var timeout: Task<Void, Never>?
    init(_ continuation: CheckedContinuation<String, Error>) { self.continuation = continuation }
    func start(_ data: Data) {
        let name = (Bundle.main.bundleIdentifier ?? "devplaceholder.YDHGHCQE.Premiere-Versions") + ".IconService"
        let connection = NSXPCConnection(serviceName: name)
        self.connection = connection
        connection.remoteObjectInterface = NSXPCInterface(with: PVIconServiceProtocol.self)
        connection.invalidationHandler = { Task { @MainActor in self.finish(false, "Could not prepare the Premiere plugin.") } }
        connection.interruptionHandler = { Task { @MainActor in self.finish(false, "Could not prepare the Premiere plugin.") } }
        connection.resume()
        timeout = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            self.finish(false, "Premiere plugin preparation timed out.")
        }
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in Task { @MainActor in self.finish(false, "Could not prepare the Premiere plugin.") } }) as? PVIconServiceProtocol else {
            finish(false, "Could not prepare the Premiere plugin."); return
        }
        proxy.installPremiereBridge(data) { ok, message in Task { @MainActor in self.finish(ok, message) } }
    }
    private func finish(_ ok: Bool, _ message: String) {
        guard let continuation else { return }; self.continuation = nil
        timeout?.cancel(); timeout = nil
        connection?.invalidationHandler = nil; connection?.interruptionHandler = nil
        connection?.invalidate(); connection = nil
        if ok { continuation.resume(returning: message) }
        else { continuation.resume(throwing: PremiereBridge.Failure(message: message)) }
    }
}
