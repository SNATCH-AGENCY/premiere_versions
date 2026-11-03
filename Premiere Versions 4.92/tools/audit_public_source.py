"""Audit a prepared source tree without printing matched secrets or private paths."""
from pathlib import Path
import re,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parents[1]
patterns={
 'private-key material':rb'-----BEGIN [A-Z ]*PRIVATE KEY-----',
 'GitHub credential':rb'\b(?:gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})',
 'AWS credential':rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b',
 'API credential':rb'\bsk-[A-Za-z0-9_-]{24,}',
 'personal home path':rb'/Users/[A-Za-z0-9_.-]+/',
}
findings=[];count=0
for p in root.rglob('*'):
 if '.git' in p.relative_to(root).parts or not p.is_file() or p.is_symlink():continue
 count+=1;relative=str(p.relative_to(root));data=p.read_bytes()
 if p.name in ['.DS_Store','usercolor.png','userprevcolor.png'] or p.suffix in ['.log','.prproj','.p12','.p8','.pem','.key','.mobileprovision']:
  findings.append((relative,'excluded/private file type'))
 for label,pattern in patterns.items():
  if re.search(pattern,data):findings.append((relative,label))
 if p.suffix.lower()=='.png':
  i=8
  while i+12<=len(data):
   n=int.from_bytes(data[i:i+4],'big');kind=data[i+4:i+8];i+=n+12
   if kind in [b'eXIf',b'tEXt',b'zTXt',b'iTXt']:findings.append((relative,'image metadata'))
if findings:
 for path,reason in findings:print('REVIEW:',path,'—',reason)
 raise SystemExit(1)
print('PASS:',count,'source files checked; no targeted credential patterns, personal home paths, user projects/history, logs or PNG metadata found. This is a scoped scan, not a complete security audit.')
