import Foundation
import Security

/// Exposes one fixed hotkey preference only to its owning helper executable.
final class Preferences: NSObject, PVHelperPreferencesProtocol {
    static var owner: URL { Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath() }
    static func validPeer(_ pid: pid_t) -> Bool {
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil,[kSecGuestAttributePid:pid] as CFDictionary,[],&code)==errSecSuccess,let code else{return false}
        var staticCode:SecStaticCode?
        guard SecCodeCopyStaticCode(code,[],&staticCode)==errSecSuccess,let staticCode else{return false}
        var info:CFDictionary?
        guard SecCodeCopySigningInformation(staticCode,SecCSFlags(rawValue:kSecCSSigningInformation),&info)==errSecSuccess,
              let values=info as? [String:Any],let executable=values[kSecCodeInfoMainExecutable as String] as? URL,
              let expected=Bundle(url:owner)?.executableURL else{return false}
        return executable.resolvingSymlinksInPath()==expected.resolvingSymlinksInPath()
    }
    func readShortcut(reply: @escaping (Data?) -> Void) {
        guard let domain=Bundle(url:Self.owner)?.bundleIdentifier else{reply(nil);return}
        CFPreferencesSynchronize(domain as CFString,kCFPreferencesCurrentUser,kCFPreferencesAnyHost)
        let value=CFPreferencesCopyValue("globalSaveShortcut" as CFString,domain as CFString,kCFPreferencesCurrentUser,kCFPreferencesAnyHost) as? Data
        guard let value,value.count<=512 else{reply(nil);return}
        reply(value)
    }
}
final class Listener:NSObject,NSXPCListenerDelegate {
    func listener(_ listener:NSXPCListener,shouldAcceptNewConnection connection:NSXPCConnection)->Bool {
        guard Preferences.validPeer(connection.processIdentifier) else{return false}
        connection.exportedInterface=NSXPCInterface(with:PVHelperPreferencesProtocol.self);connection.exportedObject=Preferences();connection.resume();return true
    }
}
@main struct Main {
    static func main(){let listener=NSXPCListener.service();let delegate=Listener();listener.delegate=delegate;listener.resume();withExtendedLifetime(delegate){RunLoop.current.run()}}
}
