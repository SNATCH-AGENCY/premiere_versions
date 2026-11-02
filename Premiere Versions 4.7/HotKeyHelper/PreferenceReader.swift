import Foundation
@MainActor enum HelperPreferenceReader {
    static func read() async -> Data? {
        await withCheckedContinuation { continuation in
            let request=HelperPreferenceRequest(continuation);request.start()
        }
    }
}
@MainActor private final class HelperPreferenceRequest {
    var continuation:CheckedContinuation<Data?,Never>?
    var connection:NSXPCConnection?
    var timeout:Task<Void,Never>?
    init(_ continuation:CheckedContinuation<Data?,Never>){self.continuation=continuation}
    func start(){
        let connection=NSXPCConnection(serviceName:(Bundle.main.bundleIdentifier ?? "")+".Preferences")
        self.connection=connection;connection.remoteObjectInterface=NSXPCInterface(with:PVHelperPreferencesProtocol.self)
        connection.invalidationHandler={Task{@MainActor in self.finish(nil)}}
        connection.interruptionHandler={Task{@MainActor in self.finish(nil)}}
        connection.resume()
        timeout=Task{@MainActor in do{try await Task.sleep(nanoseconds:8_000_000_000)}catch{return};self.finish(nil)}
        guard let proxy=connection.remoteObjectProxyWithErrorHandler({_ in Task{@MainActor in self.finish(nil)}}) as? PVHelperPreferencesProtocol else{finish(nil);return}
        proxy.readShortcut{data in Task{@MainActor in self.finish(data)}}
    }
    func finish(_ data:Data?){
        guard let continuation else{return};self.continuation=nil;timeout?.cancel();timeout=nil
        connection?.invalidationHandler=nil;connection?.interruptionHandler=nil;connection?.invalidate();connection=nil
        continuation.resume(returning:data)
    }
}
