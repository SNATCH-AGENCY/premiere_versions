"""Create signed release artifacts using the official Keychain-backed Sparkle tools. Never publishes."""
from pathlib import Path
import argparse,hashlib,json,plistlib,subprocess,sys,zipfile
parser=argparse.ArgumentParser();parser.add_argument('app',type=Path);parser.add_argument('output',type=Path);args=parser.parse_args()
root=Path(__file__).resolve().parents[1];app=args.app.resolve();output=args.output.resolve();output.mkdir(parents=True,exist_ok=True)
info=plistlib.loads((app/'Contents/Info.plist').read_bytes());version=info['CFBundleShortVersionString'];build=str(info['PVBuildNumber'])
subprocess.run([sys.executable,str(root/'tools/distribution_preflight.py'),str(app)],check=True)
archive=output/f'Premiere-Versions-{version}-Build-{build}.zip'
if archive.exists():
    with zipfile.ZipFile(archive) as existing:
        for path in (app/'Contents').rglob('*'):
            if path.is_file() and not path.is_symlink():
                name=app.name+'/'+path.relative_to(app).as_posix()
                if hashlib.sha256(existing.read(name)).digest()!=hashlib.sha256(path.read_bytes()).digest():
                    raise SystemExit('Existing archive differs from this app. Choose another output folder; nothing overwritten.')
    print('Existing archive matches the app; resuming signing.')
else:
    subprocess.run([sys.executable,str(root/'tools/release_zip.py'),str(app),str(archive)],check=True)
# Compatibility download alias redirects to the organization; older apps only trust this path.
account='devplaceholder.YDHGHCQE.Premiere-Versions'
subprocess.run([str(root/'Vendor/bin/generate_appcast'),'--account',account,'--download-url-prefix',f'https://github.com/pewakkk/premiere_versions/releases/download/v{version}-build{build}/','--link','https://github.com/SNATCH-AGENCY/premiere_versions','--versions',info['CFBundleVersion'],str(output)],check=True)
if not (output/'appcast.xml').exists():raise SystemExit('Official generator did not produce appcast.xml.')
(output/'checksums.json').write_text(json.dumps({'version':version,'build':build,'machineVersion':info['CFBundleVersion'],'archive':archive.name,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest()},indent=2)+'\n')
print('Signed artifacts prepared. Nothing was uploaded. A successful real update test is still required.')
