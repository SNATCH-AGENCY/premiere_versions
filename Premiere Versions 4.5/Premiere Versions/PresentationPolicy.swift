import Combine
import SwiftUI
import Foundation

struct PVPanelFade: ViewModifier {
    var amount: Double
    func body(content: Content) -> some View { content.opacity(1 - amount).blur(radius: amount * 12).scaleEffect(1 - amount * 0.015) }
}

@MainActor final class PVScrollMemory: ObservableObject {
    var offset: CGFloat = 0
    var closedAt: Date?
    func prepareToOpen(now: Date = Date()) {
        if let closedAt, now.timeIntervalSince(closedAt) >= 10 { offset = 0 }
        closedAt = nil
    }
}
