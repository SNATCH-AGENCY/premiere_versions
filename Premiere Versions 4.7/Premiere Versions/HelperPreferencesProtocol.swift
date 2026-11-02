import Foundation
@objc(PVHelperPreferencesProtocol)
protocol PVHelperPreferencesProtocol {
    func readShortcut(reply: @escaping (Data?) -> Void)
}
