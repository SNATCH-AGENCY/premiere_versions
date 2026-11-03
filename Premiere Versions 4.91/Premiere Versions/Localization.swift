import Foundation

/// Localizes app-owned messages only. Never pass user input, filenames or paths here.
nonisolated enum PVLocalization {
    private struct Entry: Decodable, Sendable { let ru: String; let en: String }
    private static let entries: [Entry] = {
        guard let url = Bundle.main.url(forResource: "Translations", withExtension: "json"),
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return value
    }()
    static func text(_ text: String, language: String? = nil) -> String {
        let english = (language ?? UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "en") != "ru"
        for entry in entries {
            if text == entry.ru || text == entry.en { return english ? entry.en : entry.ru }
        }
        // Match message templates without translating any interpolated user value.
        for entry in entries where entry.ru.contains("%@") {
            for source in [entry.ru, entry.en] {
                let parts = source.components(separatedBy: "%@")
                let pattern = "\\A" + parts.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "([\\s\\S]*?)") + "\\z"
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { continue }
                let values = (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
                let target = (english ? entry.en : entry.ru).components(separatedBy: "%@")
                var result = target[0]
                for i in values.indices { result += values[i] + target[i + 1] }
                return result
            }
        }
        return text
    }
}
nonisolated func PVL(_ text: String) -> String { PVLocalization.text(text) }
