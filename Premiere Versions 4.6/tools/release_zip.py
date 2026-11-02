"""Package an approved pristine release only after distribution preflight succeeds."""
from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parents[1]
if len(sys.argv)!=3:raise SystemExit('Usage: python3 tools/release_zip.py /path/to/app.app /path/to/output.zip')
app=Path(sys.argv[1]).resolve();output=Path(sys.argv[2]).resolve()
if output.exists():raise SystemExit('Refusing to overwrite an existing archive.')
subprocess.run([sys.executable,str(root/'tools/distribution_preflight.py'),str(app)],check=True)
subprocess.run(['/usr/bin/ditto','-c','-k','--sequesterRsrc','--keepParent',str(app),str(output)],check=True)
print(output)
