import Foundation

@objc(PVIconServiceProtocol)
protocol PVIconServiceProtocol {
    func consumeBackgroundLaunch(reply: @escaping (Bool) -> Void)
    func configureHotKeyHelper(_ data: Data, reply: @escaping (Bool, String) -> Void)
    func applyIcon(_ png: Data, targetPath: String, reply: @escaping (Bool, String) -> Void)
}
