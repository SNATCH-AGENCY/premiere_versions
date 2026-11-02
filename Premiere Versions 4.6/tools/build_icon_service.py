"""Build the narrow embedded XPC service before signing its enclosing app."""
from pathlib import Path
import argparse, os, plistlib, subprocess, tempfile

def build(root, app, identifier, *, testing=False):
    root,app=Path(root),Path(app)
    service=app/'Contents/XPCServices/PVIconService.xpc'
    binary=service/'Contents/MacOS/PVIconService';binary.parent.mkdir(parents=True,exist_ok=True)
    info={'CFBundleIdentifier':identifier+'.IconService','CFBundleExecutable':'PVIconService',
          'CFBundleName':'PVIconService','CFBundlePackageType':'XPC!',
          'CFBundleVersion':'1','XPCService':{'ServiceType':'Application','RunLoopType':'NSRunLoop'}}
    (service/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    modules=Path(os.environ.get('DERIVED_FILE_DIR',str(app.parent)))/'PVIconServiceModules'
    sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
    args=['xcrun','swiftc','-parse-as-library','-O','-swift-version','5','-module-cache-path',str(modules),'-sdk',sdk]
    arch=os.environ.get('CURRENT_ARCH','arm64')
    if arch not in ['arm64','x86_64']:arch='arm64'
    args+=['-target',arch+'-apple-macos'+os.environ.get('MACOSX_DEPLOYMENT_TARGET','26.6.2')]
    if testing:args+=['-D','PV_ICON_TESTING']
    args+=[str(root/'Premiere Versions/IconServiceProtocol.swift'),str(root/'IconService/Service.swift'),'-o',str(binary)]
    subprocess.run(args,check=True)
    identity=os.environ.get('EXPANDED_CODE_SIGN_IDENTITY','') or '-'
    subprocess.run(['codesign','--force','--sign',identity,str(service)],check=True)
    return service

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--app',type=Path);args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    app=args.app or Path(os.environ['TARGET_BUILD_DIR'])/os.environ['CONTENTS_FOLDER_PATH']
    if not args.app:app=app.parent
    build(root,app,'devplaceholder.YDHGHCQE.Premiere-Versions')
