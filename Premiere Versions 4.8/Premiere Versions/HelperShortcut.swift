import Foundation
import Carbon

nonisolated struct PVHelperShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String
    var launchWithPremiere: Bool? = nil
    static let `default` = Self(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey), keyLabel: "S")
    var isValid: Bool {
        let allowed = UInt32(cmdKey | controlKey | optionKey | shiftKey)
        return keyCode <= 127 && keyCode != UInt32(kVK_Escape) && modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 &&
            modifiers & ~allowed == 0 && !keyLabel.isEmpty && keyLabel.count <= 12 &&
            !keyLabel.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}
nonisolated enum PVHelperPolicy {
    static let implementationVersion = 2
    static func needsRefresh(enabled: Bool, registeredVersion: Int) -> Bool { enabled && registeredVersion != implementationVersion }
    static func shouldListen(mainRunning: Bool, premiereActive: Bool, enabled: Bool = true) -> Bool { enabled && !mainRunning && premiereActive }
}

nonisolated enum PVBackupMode: String, CaseIterable, Sendable {
    case off, automatic, always
    var title: String { switch self { case .off: return "Выкл."; case .automatic: return "Авто"; case .always: return "Всегда" } }
    func runs(premiereRunning: Bool) -> Bool { self == .always || (self == .automatic && premiereRunning) }
    static func migrate(in defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: "backupMode") == nil else { return }
        let previous = defaults.object(forKey: "autosaveMonitoringEnabled") as? Bool
        defaults.set(previous == false ? Self.off.rawValue : Self.automatic.rawValue, forKey: "backupMode")
    }
}
nonisolated enum PVPremiereProcess {
    static func matches(_ id: String?) -> Bool {
        guard let id = id?.lowercased() else { return false }
        return id == "com.adobe.premierepro" || id.hasPrefix("com.adobe.premierepro.")
    }
}
nonisolated struct PVAutoLaunchPolicy {
    private(set) var seen = Set<Int32>()
    mutating func shouldLaunch(processes: Set<Int32>, enabled: Bool, ownerRunning: Bool, justEnabled: Bool = false) -> Bool {
        let started = !processes.subtracting(seen).isEmpty
        seen = processes
        return enabled && !ownerRunning && !processes.isEmpty && (started || justEnabled)
    }
}
