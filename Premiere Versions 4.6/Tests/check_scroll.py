from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
s=(root/'Premiere Versions/InteractionControls.swift').read_text()
s=s[s.index('nonisolated enum PVScrollPhase'):s.index('struct PVStageScrollCapture:')]
harness=r'''
var gate = PVScrollGate()
assert(gate.direction(delta: -5, precise: true, phase: .began, time: 0) == nil)
assert(gate.direction(delta: -14, precise: true, phase: .changed, time: 0.02) == 1)
assert(gate.direction(delta: 90, precise: true, phase: .changed, time: 0.04) == nil)
assert(gate.direction(delta: -90, precise: true, phase: .changed, time: 0.06) == nil)
assert(gate.direction(delta: 0, precise: true, phase: .ended, time: 0.07) == nil)
assert(gate.direction(delta: 80, precise: true, phase: .momentum, time: 0.1) == nil)
assert(gate.direction(delta: 80, precise: true, phase: .momentum, time: 0.2) == nil)
assert(gate.direction(delta: 20, precise: true, phase: .began, time: 0.25) == -1)
var wheel = PVScrollGate()
assert(wheel.direction(delta: -3, precise: false, phase: .discrete, time: 1) == 1)
for i in 1...10 { assert(wheel.direction(delta: 3, precise: false, phase: .discrete, time: 1 + Double(i) * 0.1) == nil) }
assert(wheel.direction(delta: 3, precise: false, phase: .discrete, time: 2.4) == -1)
var jitter = PVScrollGate()
assert(jitter.direction(delta: -10, precise: true, phase: .began, time: 0) == nil)
assert(jitter.direction(delta: 10, precise: true, phase: .changed, time: 0.1) == nil)
assert(jitter.direction(delta: -10, precise: true, phase: .changed, time: 0.2) == nil)
assert(jitter.direction(delta: 0, precise: true, phase: .cancelled, time: 0.3) == nil)
assert(jitter.direction(delta: -20, precise: true, phase: .began, time: 0.4) == 1)
print("PASS: trackpad threshold, one transition per gesture, no momentum reversal, discrete wheel burst debounce and direction changes")
'''
with tempfile.TemporaryDirectory(prefix='pv41-scroll-check-') as tmp:
    tmp=Path(tmp);source=tmp/'ScrollChecks.swift';source.write_text('import Foundation\n'+s+harness)
    sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
    compiler=subprocess.check_output(['xcrun','--find','swiftc'],text=True).strip()
    subprocess.run([compiler,'-sdk',sdk,'-module-cache-path',str(tmp/'modules'),str(source),'-o',str(tmp/'checks')],check=True)
    subprocess.run([str(tmp/'checks')],check=True)
