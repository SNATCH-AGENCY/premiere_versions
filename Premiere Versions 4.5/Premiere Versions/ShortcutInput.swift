import Combine
import AppKit
import Carbon

@MainActor final class PVShortcutInput: ObservableObject {
    private var previous: TISInputSource?
    func begin() {
        guard previous == nil else { return }
        previous = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        for identifier in ["com.apple.keylayout.ABC", "com.apple.keylayout.US"] {
            let filter = [kTISPropertyInputSourceID as String: identifier] as CFDictionary
            let sources = TISCreateInputSourceList(filter, false).takeRetainedValue() as! [TISInputSource]
            if let source = sources.first, TISSelectInputSource(source) == noErr { return }
        }
    }
    func end() { if let previous { TISSelectInputSource(previous) }; previous = nil }
    static func latinLabel(code: UInt16, fallback: String) -> String {
        let labels: [UInt16:String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"-",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",50:"`",65:".",67:"*",69:"+",75:"/",76:"⌤",78:"-",81:"=",82:"0",83:"1",84:"2",85:"3",86:"4",87:"5",88:"6",89:"7",91:"8",92:"9"]
        return labels[code] ?? fallback
    }
}
