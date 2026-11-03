"""Sign the immutable CEP payload with a private certificate kept outside the source tree."""
from pathlib import Path
import argparse,hashlib,json,os,shutil,subprocess,tempfile,zipfile

def sign(root, tool, cert, password_file, *, timestamp='http://timestamp.digicert.com'):
 root=Path(root);payload=root/'BridgePlugin'
 secret=Path(password_file).read_text().strip()
 with tempfile.TemporaryDirectory(prefix='pv-cep-sign-') as temporary:
  stage=Path(temporary)/'plugin';stage.mkdir()
  for file in payload.rglob('*'):
   if file.is_symlink():raise RuntimeError('Plugin symbolic links are not supported')
   relative=file.relative_to(payload)
   if relative.parts[0]=='META-INF' or str(relative)=='mimetype':continue
   if file.is_file():
    dest=stage/relative;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(file,dest)
  archive=Path(temporary)/'bridge.zxp'
  args=[str(tool),'-sign',str(stage),str(archive),str(cert),secret]
  if timestamp:args+=['-tsa',timestamp]
  result=subprocess.run(args,capture_output=True,text=True)
  if result.returncode:raise RuntimeError('CEP signing failed: '+result.stdout+result.stderr)
  subprocess.run([str(tool),'-verify',str(archive)],check=True)
  with zipfile.ZipFile(archive) as z:
   for name in ['mimetype','META-INF/signatures.xml']:
    target=payload/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(z.read(name))
  subprocess.run([str(tool),'-verify',str(payload)],check=True)
 files={str(p.relative_to(payload)):hashlib.sha256(p.read_bytes()).hexdigest() for p in payload.rglob('*') if p.is_file()}
 (root/'BridgePayload.json').write_text(json.dumps({'identifier':'dev.premiereversions.bridge','version':'4.91.1','files':files},indent=2)+'\n')

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--tool',required=True);p.add_argument('--certificate',required=True);p.add_argument('--password-file',required=True);a=p.parse_args()
 sign(Path(__file__).resolve().parents[1],a.tool,a.certificate,a.password_file)
