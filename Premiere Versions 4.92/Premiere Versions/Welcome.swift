import SwiftUI
import Foundation

nonisolated enum PVWelcomePolicy {
    static let preferenceKey = "lastCompletedWelcomeRelease"
    static func needsPresentation(version: String = AppRelease.version, build: String = AppRelease.build, defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: preferenceKey) != version + "#" + build
    }
    static func complete(version: String = AppRelease.version, build: String = AppRelease.build, defaults: UserDefaults = .standard) {
        defaults.set(version + "#" + build, forKey: preferenceKey)
    }
}

struct PVWelcomeScreen: View {
    let ink: Color
    let muted: Color
    let visible: Bool
    let continueAction: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var titleVisible = false
    @State private var hintsVisible = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Text("For every edit.")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(ink)
                    .blur(radius: titleVisible || reduceMotion ? 0 : 18)
                    .opacity(titleVisible ? 1 : 0)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                Button(action: continueAction) {
                    Text("press return").font(.system(size: 13, weight: .light))
                }
                .buttonStyle(.plain).keyboardShortcut(.defaultAction)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2 + 80)
                .opacity(hintsVisible ? 1 : 0)
                Button(action: continueAction) {
                    ZStack {
                        Text("SCROLL").fixedSize().rotationEffect(.degrees(-90))
                        Image(systemName: "arrow.down").offset(y: 48)
                    }.frame(width: 28, height: 132)
                }
                .buttonStyle(.plain).font(.system(size: 13, weight: .light))
                .position(x: geometry.size.width - 42, y: geometry.size.height / 2)
                .opacity(hintsVisible ? 1 : 0)
                VStack(spacing: 5) {
                    Text("by " + AppRelease.author)
                    Text(AppRelease.label).font(.system(size: 10, design: .monospaced))
                }.font(.system(size: 11, weight: .light))
                    .position(x: geometry.size.width / 2, y: geometry.size.height - 38)
                    .opacity(hintsVisible ? 1 : 0)
            }
            .foregroundStyle(muted.opacity(0.55))
            .background {
                PVStageScrollCapture(enabled: true) { direction in
                    if direction > 0 { continueAction() }
                }
            }
        }
        .task(id: visible) {
            guard visible else { titleVisible = false; hintsVisible = false; return }
            if !reduceMotion { try? await Task.sleep(nanoseconds: 220_000_000) }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 1.7)) { titleVisible = true }
            if !reduceMotion { try? await Task.sleep(nanoseconds: 1_800_000_000) }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) { hintsVisible = true }
        }
    }
}
