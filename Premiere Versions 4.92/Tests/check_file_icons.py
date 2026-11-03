"""Run the real embedded-service Finder icon integration check."""
from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parents[1]
if len(sys.argv)!=2:raise SystemExit('Usage: check_file_icons.py /path/to/pristine.app')
subprocess.run([sys.executable,str(root/'Tests/check_icon_quarantine.py'),sys.argv[1]],check=True)
