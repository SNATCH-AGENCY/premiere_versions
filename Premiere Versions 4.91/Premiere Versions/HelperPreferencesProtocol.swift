import Foundation
@objc(PVHelperPreferencesProtocol)
protocol PVHelperPreferencesProtocol {
    func setBackgroundLaunch(_ enabled: Bool, reply: @escaping (Bool) -> Void)
    func readShortcut(reply: @escaping (Data?) -> Void)
}
