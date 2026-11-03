import AppKit
import Foundation

/// Only the embedded service writes Finder metadata; the sandboxed app never rewrites itself.
@MainActor
enum PVFinderIconWriter {
    static func apply(_ image: NSImage, to target: URL) async -> Bool {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]), png.count <= 8_388_608 else { return false }
        return await withCheckedContinuation { continuation in
            let request = PVIconRequest(continuation)
            request.start(png: png, target: target)
        }
    }
}

@MainActor
private final class PVIconRequest {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var connection: NSXPCConnection?
    private var timeout: Task<Void, Never>?
    init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }
    func start(png: Data, target: URL) {
        let name = (Bundle.main.bundleIdentifier ?? "devplaceholder.YDHGHCQE.Premiere-Versions") + ".IconService"
        let connection = NSXPCConnection(serviceName: name)
        self.connection = connection
        connection.remoteObjectInterface = NSXPCInterface(with: PVIconServiceProtocol.self)
        connection.invalidationHandler = { Task { @MainActor in self.finish(false) } }
        connection.interruptionHandler = { Task { @MainActor in self.finish(false) } }
        connection.resume()
        timeout = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
            self.finish(false)
        }
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            NSLog("Premiere Versions: icon service unavailable: %@", error.localizedDescription)
            Task { @MainActor in self.finish(false) }
        }) as? PVIconServiceProtocol else { finish(false); return }
        proxy.applyIcon(png, targetPath: target.path) { success, message in
            if !success { NSLog("Premiere Versions: icon service: %@", message) }
            Task { @MainActor in self.finish(success) }
        }
    }
    private func finish(_ success: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel(); timeout = nil
        connection?.invalidationHandler = nil
        connection?.interruptionHandler = nil
        connection?.invalidate(); connection = nil
        continuation.resume(returning: success)
    }
}
