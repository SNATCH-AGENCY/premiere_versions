"""Fail closed until a real Sparkle-enabled, keyed and pristine release is ready."""
from pathlib import Path
import base64,plistlib,subprocess,sys
app=Path(sys.argv[1]).resolve();info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
errors=[]
expected=info['CFBundleShortVersionString']+'.'+str(info.get('PVBuildNumber',''))
if info.get('CFBundleVersion')!=expected:errors.append('Bundle build must be version.display-build (for example 4.3.1).')
try:
 key=base64.b64decode(info.get('SUPublicEDKey',''),validate=True)
 if len(key)!=32:raise ValueError()
except ValueError:errors.append('A valid public Ed25519 update key is missing. Never embed a private key.')
framework=app/'Contents/Frameworks/Sparkle.framework'
if not framework.exists():errors.append('Sparkle.framework is not bundled.')
else:
 if not list(framework.glob('Versions/*/XPCServices/Installer.xpc')):errors.append('Sparkle Installer XPC service missing.')
helper=app/'Contents/Library/LoginItems/Premiere Versions Helper.app'
if not helper.exists():errors.append('Hotkey login item missing.')
elif subprocess.run(['codesign','--verify','--strict',str(helper)],capture_output=True).returncode:errors.append('Hotkey helper signature failed.')
icon=app/'Contents/XPCServices/PVIconService.xpc'
if not icon.exists():errors.append('Embedded icon service missing.')
elif subprocess.run(['codesign','--verify','--strict',str(icon)],capture_output=True).returncode:errors.append('Icon service signature failed.')
linked=subprocess.run(['otool','-L',str(app/'Contents/MacOS'/info['CFBundleExecutable'])],capture_output=True,text=True,check=True).stdout
if 'Sparkle.framework' not in linked:errors.append('The executable was built without Sparkle; rebuild after enabling the dependency.')
if info.get('SUFeedURL')!='https://raw.githubusercontent.com/pewakkk/premiere_versions/main/docs/appcast.xml':errors.append('Unexpected update-feed URL.')
result=subprocess.run(['codesign','--verify','--deep','--strict',str(app)],capture_output=True,text=True)
if result.returncode:errors.append('Pristine signature verification failed.')
if errors:
 for error in errors:print('NOT READY:',error)
 raise SystemExit(1)
print('PASS: release metadata, public update key, linked Sparkle, installer service and pristine signature. A two-build update test is still required before publication.')
