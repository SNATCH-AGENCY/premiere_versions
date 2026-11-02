import Foundation
import Carbon

nonisolated struct PVHelperShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String
    static let `default` = Self(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey), keyLabel: "S")
    var isValid: Bool {
        let allowed = UInt32(cmdKey | controlKey | optionKey | shiftKey)
        return keyCode <= 127 && keyCode != UInt32(kVK_Escape) && modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 &&
            modifiers & ~allowed == 0 && !keyLabel.isEmpty && keyLabel.count <= 12 &&
            !keyLabel.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}
nonisolated enum PVHelperPolicy {
    static func shouldListen(mainRunning: Bool, premiereActive: Bool, enabled: Bool = true) -> Bool { enabled && !mainRunning && premiereActive }
}
