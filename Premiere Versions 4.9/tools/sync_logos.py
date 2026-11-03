"""Copy cataloged originals into the app assets; never alters custom logo history."""
from pathlib import Path
import json
import shutil
import sys
project = Path(__file__).resolve().parents[1]
logos = project.parent / 'assets/logos'
catalog = json.loads((logos / 'catalog.json').read_text())
for variant in catalog['variants']:
    source = logos / variant['file']
    target = project / 'Premiere Versions/Assets.xcassets' / (variant['asset'] + '.imageset') / 'logo.png'
    if '--check' in sys.argv:
        if source.read_bytes() != target.read_bytes():
            raise SystemExit(f"Asset out of sync: {variant['id']}")
    else:
        shutil.copyfile(source, target)
print('PASS: all cataloged originals match bundled assets')
