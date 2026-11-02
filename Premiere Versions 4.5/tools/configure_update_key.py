"""Use the official tool to keep the private key in Keychain and embed only its public key."""
from pathlib import Path
import base64,plistlib,re,subprocess,sys
root=Path(__file__).resolve().parents[1]
tool=root/'Vendor/bin/generate_keys'
if not tool.exists():raise SystemExit('Run tools/enable_sparkle.py first.')
account='devplaceholder.YDHGHCQE.Premiere-Versions'
# No -x/export operation is ever used.
result=subprocess.run([str(tool),'--account',account],capture_output=True,text=True)
if result.returncode:
 print('Keychain setup failed. Run this command from the normal macOS Terminal.',file=sys.stderr)
 print(result.stderr.strip(),file=sys.stderr)
 raise SystemExit(result.returncode)
result=subprocess.run([str(tool),'--account',account,'-p'],capture_output=True,text=True,check=True)
candidates=re.findall(r'(?<![A-Za-z0-9+/])([A-Za-z0-9+/]{43}=)(?![A-Za-z0-9+/])',result.stdout)
valid=[key for key in candidates if len(base64.b64decode(key,validate=True))==32]
if len(set(valid))!=1:raise SystemExit('Could not identify the public update key. No project changes made.')
p=root/'AppMetadata.plist';info=plistlib.loads(p.read_bytes());info['SUPublicEDKey']=valid[0];p.write_bytes(plistlib.dumps(info))
print('Ready. The private key stays in macOS Keychain. Only the public key was saved in AppMetadata.plist.')
