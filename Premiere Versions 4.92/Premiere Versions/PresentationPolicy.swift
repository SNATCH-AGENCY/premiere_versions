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

@MainActor enum PVTerminationContext { static var updating = false }

/// Retain menu navigation until the SwiftUI window has subscribed, including a cold launch.
@MainActor final class PVPanelNavigation: ObservableObject {
    static let shared = PVPanelNavigation()
    @Published var request: String?
}
