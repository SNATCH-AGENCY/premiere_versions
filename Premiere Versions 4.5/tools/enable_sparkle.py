"""Install the pinned official SDK from a verified archive and enable local framework linkage."""
from pathlib import Path
import argparse,hashlib,plistlib,shutil,subprocess,tarfile,tempfile,urllib.request
VERSION='2.10.1'
DIGEST='1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27'
URL='https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz'
parser=argparse.ArgumentParser();parser.add_argument('--archive',type=Path);args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='pv-sparkle-setup-') as temp:
 temp=Path(temp);archive=args.archive
 if archive is None:
  archive=temp/'Sparkle.tar.xz'
  urllib.request.urlretrieve(URL,archive)
 if hashlib.sha256(archive.read_bytes()).hexdigest()!=DIGEST:raise SystemExit('Official SDK archive checksum mismatch; nothing installed.')
 with tarfile.open(archive) as tar:
  for item in tar.getmembers():
   name=Path(item.name)
   if name.is_absolute() or '..' in name.parts:raise SystemExit('Unsafe archive member.')
   if item.issym() or item.islnk():
    link=Path(item.linkname)
    if link.is_absolute() or '..' in link.parts:raise SystemExit('Unsafe archive link.')
  tar.extractall(temp/'unpacked')
 vendor=root/'Vendor';target=vendor/'Sparkle.framework';vendor.mkdir(exist_ok=True)
 if target.exists():
  version=plistlib.loads((target/'Resources/Info.plist').read_bytes()).get('CFBundleShortVersionString')
  if version!=VERSION:raise SystemExit('Another SDK version is already installed. Refusing replacement.')
 else:
  shutil.copytree(temp/'unpacked/Sparkle.framework',target,symlinks=True,copy_function=shutil.copy)
 shutil.copy(temp/'unpacked/LICENSE',vendor/'Sparkle-LICENSE.txt')
 # Keep signing/release tools outside the source group and outside Git.
 if not (vendor/'bin').exists():shutil.copytree(temp/'unpacked/bin',vendor/'bin',symlinks=True,copy_function=shutil.copy)
project=root/'Premiere Versions.xcodeproj/project.pbxproj';text=project.read_text()
if '/* PV Sparkle SDK */' not in text:
 link='F43A00000000000000000001';file='F43A00000000000000000002';embed='F43A00000000000000000004';phase='F43A00000000000000000005'
 section=f'''/* Begin PBXBuildFile section */
        {link} /* Sparkle in Frameworks */ = {{isa = PBXBuildFile; fileRef = {file}; }};
        {embed} /* Sparkle in Embed Frameworks */ = {{isa = PBXBuildFile; fileRef = {file}; settings = {{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }}; }};
/* End PBXBuildFile section */
/* Begin PBXCopyFilesBuildPhase section */
        {phase} /* Embed Frameworks */ = {{isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 10; files = ({embed}, ); name = "Embed Frameworks"; runOnlyForDeploymentPostprocessing = 0; }};
/* End PBXCopyFilesBuildPhase section */
'''
 text=text.replace('/* Begin PBXFileReference section */',section+'\n/* Begin PBXFileReference section */\n'+f'        {file} /* PV Sparkle SDK */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; path = Vendor/Sparkle.framework; sourceTree = "<group>"; }};',1)
 a=text.index('/* Begin PBXFrameworksBuildPhase section */');b=text.index('/* End PBXFrameworksBuildPhase section */',a)
 part=text[a:b].replace('files = (','files = (\n                '+link+',',1);text=text[:a]+part+text[b:]
 text=text.replace('000000000000000140000000 /* Resources */,','000000000000000140000000 /* Resources */,\n                '+phase+' /* Embed Frameworks */,',1)
 text=text.replace('000000000000000000000010 /* Premiere Versions */,','000000000000000000000010 /* Premiere Versions */,\n                '+file+' /* PV Sparkle SDK */,',1)
 text=text.replace('CODE_SIGN_STYLE = Automatic;','CODE_SIGN_STYLE = Automatic;\n                FRAMEWORK_SEARCH_PATHS = ("$(inherited)", "$(PROJECT_DIR)/Vendor", );')
 backup=project.with_suffix('.pbxproj.before-sparkle')
 if backup.exists():raise SystemExit('Project backup already exists. Refusing to overwrite it.')
 backup.write_text(project.read_text());project.write_text(text)
 subprocess.run(['plutil','-lint',str(project)],check=True)
entitlements=root/'PremiereVersions.entitlements';values=plistlib.loads(entitlements.read_bytes())
values['com.apple.security.temporary-exception.mach-lookup.global-name']=['$(PRODUCT_BUNDLE_IDENTIFIER)-spks','$(PRODUCT_BUNDLE_IDENTIFIER)-spki']
entitlements.write_bytes(plistlib.dumps(values))
print('Official Sparkle 2.10.1 SDK verified and configured. Vendor/bin contains the official key/signing tools; private keys must stay in Keychain, outside this project.')
