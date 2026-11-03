import Foundation
import Combine

/// A snapshot refreshed by project/save events, never by a SwiftUI body evaluation.
@MainActor final class PVManualVersionIndex: ObservableObject {
    @Published private(set) var numbers: [Int]?
    private(set) var directoryReads = 0

    func invalidate() { numbers = nil }

    func refresh(project: String, archive: URL, fileManager: FileManager = .default, directory: URL? = nil) throws {
        guard !project.isEmpty else { invalidate(); return }
        do {
            let folder = directory ?? archive.appendingPathComponent(project, isDirectory: true)
            guard fileManager.fileExists(atPath: folder.path) else { numbers = []; return }
            directoryReads += 1
            let files = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            let metadata = try? Data(contentsOf: folder.appendingPathComponent(".pv-source.json"))
            let aliases = metadata.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["names"] as? [String] ?? []
            let prefix = ([project] + aliases).map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
            let regex = try NSRegularExpression(pattern: "(?i)^(?:" + prefix + ")" + #"_v(\d+)(?:_|\.|$)"#)
            let found = files.compactMap { file -> Int? in
                guard file.pathExtension.lowercased() == "prproj" else { return nil }
                let name = file.lastPathComponent
                let range = NSRange(name.startIndex..<name.endIndex, in: name)
                guard let match = regex.firstMatch(in: name, range: range),
                      let numberRange = Range(match.range(at: 1), in: name) else { return nil }
                return Int(name[numberRange])
            }
            let ordered = found.sorted()
            if numbers != ordered { numbers = ordered }
        } catch { invalidate(); throw error }
    }
}
