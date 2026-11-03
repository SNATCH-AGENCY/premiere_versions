"""Deliver the stable Premiere Versions.app path; preserve version/build archives."""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess
import sys
import uuid


def release_key(info):
    parts = tuple(int(n) for n in str(info['CFBundleShortVersionString']).split('.'))
    return (parts + (0,) * max(0, 3-len(parts)), int(info.get('PVBuildNumber', info['CFBundleVersion'])))


source = Path(sys.argv[1]).resolve()
with (source/'Contents/Info.plist').open('rb') as stream:
    info = plistlib.load(stream)
executable = Path('Contents/MacOS')/info['CFBundleExecutable']
if not os.access(source/executable, os.X_OK):
    raise SystemExit('Source application is not executable')
output = Path(__file__).resolve().parents[2]
output.mkdir(exist_ok=True)
target = output/'Premiere Versions.app'
archives = []
for app in output.glob('Premiere Versions*.app'):
    with (app/'Contents/Info.plist').open('rb') as stream:
        old = plistlib.load(stream)
    if old.get('CFBundleIdentifier') != info.get('CFBundleIdentifier'):
        continue
    if release_key(old) >= release_key(info):
        raise SystemExit('This release or a newer release is already present; refusing replacement')
    archive = output/'old versions/builds'/('Premiere Versions '+str(old['CFBundleShortVersionString']))/('Build '+str(old.get('PVBuildNumber', old['CFBundleVersion'])))/app.name
    if archive.exists():
        raise SystemExit('Archive destination already exists; leaving every build untouched')
    archives.append((app, archive))
if target.exists() and not any(app == target for app, _ in archives):
    raise SystemExit('Target belongs to another application; refusing replacement')
staging = output/('.pv-'+uuid.uuid4().hex+'.app')
moved = []
try:
    shutil.copytree(source, staging, copy_function=shutil.copy, symlinks=True)
    if not os.access(staging/executable, os.X_OK):
        raise RuntimeError('Packaged executable has no execution permission')
    subprocess.run(['codesign','--verify','--deep','--strict',str(staging)],check=True)
    try:
        for app, archive in archives:
            archive.parent.mkdir(parents=True,exist_ok=True)
            app.rename(archive)
            moved.append((app,archive))
        staging.rename(target)
    except BaseException:
        for app,archive in reversed(moved):
            if archive.exists() and not app.exists(): archive.rename(app)
        raise
finally:
    if staging.exists(): shutil.rmtree(staging)
print(target)
