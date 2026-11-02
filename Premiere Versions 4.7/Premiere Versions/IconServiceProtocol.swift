import Foundation

@objc(PVIconServiceProtocol)
protocol PVIconServiceProtocol {
    func configureHotKeyHelper(_ data: Data, reply: @escaping (Bool, String) -> Void)
    func applyIcon(_ png: Data, targetPath: String, reply: @escaping (Bool, String) -> Void)
}
