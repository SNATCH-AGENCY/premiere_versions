import Combine
import Foundation
import AppKit
import Darwin

nonisolated enum PVProjectLocation {
    static func nearestFolder(to location: URL, fileManager: FileManager = .default) -> URL {
        var candidate = location.standardizedFileURL
        while true {
            var directory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &directory), directory.boolValue,
               fileManager.isReadableFile(atPath: candidate.path) { return candidate }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path { return fileManager.homeDirectoryForCurrentUser }
            candidate = parent
        }
    }
}

/// An open file descriptor keeps watching deletion/rename without polling the disk.
@MainActor final class PVProjectWatcher: ObservableObject {
    @Published private(set) var revision = 0
    private var stream: DispatchSourceFileSystemObject?
    private var scope: URL?
    func watch(_ url: URL?) {
        stop()
        guard let url else { return }
        if url.startAccessingSecurityScopedResource() { scope = url }
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { stop(); return }
        let stream = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.delete, .rename, .revoke], queue: .main)
        stream.setEventHandler { [weak self] in Task { @MainActor in self?.revision &+= 1 } }
        stream.setCancelHandler { close(descriptor) }
        self.stream = stream
        stream.resume()
    }
    func stop() {
        stream?.cancel(); stream = nil
        scope?.stopAccessingSecurityScopedResource(); scope = nil
    }
    deinit { stream?.cancel(); scope?.stopAccessingSecurityScopedResource() }
}
