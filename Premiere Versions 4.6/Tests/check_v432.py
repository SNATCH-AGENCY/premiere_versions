from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
s=(root/'Premiere Versions/UtilityInteraction.swift').read_text()
model=s[s.index('nonisolated struct PVHSVComponents'):s.index('/// Embedded color wheel')]
harness=r'''
func check(_ value: Bool, _ reason: String) { if !value { print("FAIL:",reason); exit(1) } }
func near(_ a:Double,_ b:Double)->Bool { abs(a-b)<0.00001 }
let red=PVHSVComponents.wheel(point:CGPoint(x:100,y:50),diameter:100,brightness:0.5)
check(near(red.color.redComponent,0.5) && near(red.color.greenComponent,0) && near(red.color.blueComponent,0),"red wheel edge")
let cyan=PVHSVComponents.wheel(point:CGPoint(x:0,y:50),diameter:100,brightness:1)
check(near(cyan.color.redComponent,0) && near(cyan.color.greenComponent,1) && near(cyan.color.blueComponent,1),"opposite hue")
let neutral=PVHSVComponents.wheel(point:CGPoint(x:50,y:50),diameter:100,brightness:0.7)
check(near(neutral.color.redComponent,0.7) && near(neutral.color.greenComponent,0.7) && near(neutral.color.blueComponent,0.7),"neutral wheel center")
let lifted=PVHSVComponents.wheel(point:CGPoint(x:100,y:50),diameter:100,brightness:0)
check(lifted.brightness==1,"wheel remains usable when initial color is black")
let bounded=PVHSVComponents.wheel(point:CGPoint(x:150,y:50),diameter:100,brightness:1)
check(bounded.saturation==1,"drag outside wheel clamps saturation")
let original=NSColor(srgbRed:0.34,green:0.52,blue:0.8,alpha:1)
let converted=PVHSVComponents(color:original).color
check(near(converted.redComponent,0.34) && near(converted.greenComponent,0.52) && near(converted.blueComponent,0.8),"RGB HSV round trip")
print("PASS: color wheel hue/saturation geometry, value, initial black usability, bounds and RGB/HSV round trip")
'''
with tempfile.TemporaryDirectory(prefix='pv432-colors-') as tmp:
 p=Path(tmp);swift=p/'Checks.swift';swift.write_text('import Foundation\nimport AppKit\n'+model+harness)
 subprocess.run(['xcrun','swiftc','-module-cache-path',str(p/'modules'),str(swift),'-o',str(p/'Checks')],check=True)
 subprocess.run([str(p/'Checks')],check=True)
