import Combine
import SwiftUI
import Foundation

@MainActor final class PVScrollMemory: ObservableObject {
    var offset: CGFloat = 0
    var closedAt: Date?
    func prepareToOpen(now: Date = Date()) {
        if let closedAt, now.timeIntervalSince(closedAt) >= 10 { offset = 0 }
        closedAt = nil
    }
}
