import Foundation

@objc(PVIconServiceProtocol)
protocol PVIconServiceProtocol {
    func applyIcon(_ png: Data, targetPath: String, reply: @escaping (Bool, String) -> Void)
}
