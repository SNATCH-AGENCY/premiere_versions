"""Real Sparkle update test in two isolated, sandboxed fixture apps. Run from normal Terminal."""
from pathlib import Path
import argparse,base64,hashlib,http.server,json,os,plistlib,re,shutil,subprocess,tempfile,threading,time,uuid
root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path);args=parser.parse_args()
metadata=plistlib.loads((root/'AppMetadata.plist').read_bytes());public=metadata.get('SUPublicEDKey','')
if len(base64.b64decode(public))!=32:raise SystemExit('Configure the public update key first.')
fixture=Path(tempfile.mkdtemp(prefix='pv-real-update-',dir='/private/tmp'))
identity='devplaceholder.PVUpdateFixture.'+uuid.uuid4().hex
server=None;process=None
class Quiet(http.server.SimpleHTTPRequestHandler):
 def log_message(self,*args):pass
try:
 web=fixture/'web';web.mkdir();installed=fixture/'Installed';installed.mkdir()
 for source,target in [('PVGraphite','current.png'),('PVPearl','previous.png')]:
  shutil.copy(root/'Premiere Versions/Assets.xcassets'/(source+'.imageset')/'logo.png',fixture/target)
 def handler(*a,**kw):return Quiet(*a,directory=str(web),**kw)
 server=http.server.ThreadingHTTPServer(('127.0.0.1',0),handler)
 threading.Thread(target=server.serve_forever,daemon=True).start();port=server.server_address[1]
 binary=fixture/'Fixture'
 subprocess.run(['xcrun','swiftc','-parse-as-library','-disable-sandbox','-swift-version','5','-default-isolation','MainActor','-F',str(root/'Vendor'),'-framework','Sparkle','-Xlinker','-rpath','-Xlinker','@executable_path/../Frameworks','-module-cache-path',str(fixture/'modules'),str(root/'Tests/SparkleUpdateFixture.swift'),'-o',str(binary)],check=True)
 entitlements=fixture/'fixture.entitlements'
 entitlements.write_bytes(plistlib.dumps({'com.apple.security.app-sandbox':True,'com.apple.security.network.client':True,'com.apple.security.files.bookmarks.app-scope':True,'com.apple.security.temporary-exception.files.absolute-path.read-write':[str(fixture)+'/'],'com.apple.security.temporary-exception.mach-lookup.global-name':[identity+'-spks',identity+'-spki']}))
 def build_app(folder,version,phase):
  app=folder/'PV Update Fixture.app';contents=app/'Contents';(contents/'MacOS').mkdir(parents=True);(contents/'Frameworks').mkdir()
  shutil.copy(binary,contents/'MacOS/Fixture')
  shutil.copytree(root/'Vendor/Sparkle.framework',contents/'Frameworks/Sparkle.framework',symlinks=True,copy_function=shutil.copy)
  info={'CFBundleExecutable':'Fixture','CFBundleIdentifier':identity,'CFBundleName':'PV Update Fixture','CFBundlePackageType':'APPL','CFBundleVersion':version,'CFBundleShortVersionString':'4.3','LSUIElement':True,'NSPrincipalClass':'NSApplication','CFBundleDevelopmentRegion':'en','PVFixtureRoot':str(fixture),'PVFixturePhase':phase,'SUPublicEDKey':public,'SUFeedURL':f'http://127.0.0.1:{port}/appcast.xml','SUEnableAutomaticChecks':False,'SUAutomaticallyUpdate':False,'SUEnableSystemProfiling':False,'SUEnableInstallerLauncherService':True,'SUVerifyUpdateBeforeExtraction':True,'NSAppTransportSecurity':{'NSAllowsArbitraryLoads':True}}
  (contents/'Info.plist').write_bytes(plistlib.dumps(info))
  subprocess.run(['codesign','--force','--sign','-','--entitlements',str(entitlements),str(app)],check=True,capture_output=True)
  subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
  return app
 base=build_app(installed,'4.3.1','bad');target=build_app(fixture/'Target','4.3.2','good')
 archive=web/'valid.zip';subprocess.run(['ditto','-c','-k','--keepParent',str(target),str(archive)],check=True)
 result=subprocess.run([str(root/'Vendor/bin/sign_update'),'--account','devplaceholder.YDHGHCQE.Premiere-Versions','-p',str(archive)],capture_output=True,text=True)
 if result.returncode:raise RuntimeError('Keychain signing failed. Run this test from normal Terminal. '+result.stderr.strip())
 matches=re.findall(r'(?<![A-Za-z0-9+/])([A-Za-z0-9+/]{86}==)(?![A-Za-z0-9+/])',result.stdout)
 if len(matches)!=1:raise RuntimeError('Official signer did not return one valid update signature.')
 signature=matches[0]
 bad=web/'tampered.zip';bad.write_bytes(archive.read_bytes()+b'tampered')
 def feed(name):
  selected=web/name
  xml=f'''<?xml version="1.0"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Isolated local fixture</title><item><title>Fixture 4.3.2</title><sparkle:version>4.3.2</sparkle:version><sparkle:shortVersionString>4.3</sparkle:shortVersionString><enclosure url="http://127.0.0.1:{port}/{name}" sparkle:edSignature="{signature}" length="{selected.stat().st_size}" type="application/octet-stream"/></item></channel></rss>'''
  (web/'appcast.xml').write_text(xml)
 def wait_stage(expected,timeout=100):
  deadline=time.monotonic()+timeout
  while time.monotonic()<deadline:
   path=fixture/'result.json'
   if path.exists():
    try:state=json.loads(path.read_text())
    except (ValueError,OSError):time.sleep(.1);continue
    if state.get('stage')=='failed':raise RuntimeError('Fixture failed: '+json.dumps(state))
    if state.get('stage')==expected:return state
   time.sleep(.2)
  raise RuntimeError('Update fixture timed out; see '+str(fixture/'fixture.log'))
 log=(fixture/'fixture.log').open('w')
 feed('tampered.zip')
 process=subprocess.Popen([str(base/'Contents/MacOS/Fixture')],stdout=log,stderr=log)
 rejected=wait_stage('tamper-rejected');process.wait(timeout=20);process=None
 assert plistlib.loads((base/'Contents/Info.plist').read_bytes())['CFBundleVersion']=='4.3.1','Tampered archive replaced baseline'
 info=plistlib.loads((base/'Contents/Info.plist').read_bytes());info['PVFixturePhase']='good';(base/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
 subprocess.run(['codesign','--force','--sign','-','--entitlements',str(entitlements),str(base)],check=True,capture_output=True)
 (fixture/'result.json').unlink();feed('valid.zip')
 process=subprocess.Popen([str(base/'Contents/MacOS/Fixture')],stdout=log,stderr=log)
 state=wait_stage('updated');process.wait(timeout=20);process=None
 actual=plistlib.loads((base/'Contents/Info.plist').read_bytes())
 assert actual['CFBundleVersion']=='4.3.2' and state['preserved'] and state['finderIcon']
 subprocess.run(['codesign','--verify','--deep',str(base)],check=True)
 report={'passed':True,'tamperedArchiveRejected':True,'installedVersion':'4.3.2','relaunchVerified':True,'folderBookmarkLanguageShortcutAndTwoLogoSlotsPreserved':True,'finderIconRestored':True,'fixtureBundleID':identity}
 if args.output:args.output.write_text(json.dumps(report,indent=2)+'\n')
 print('PASS: real Sparkle rejected a tampered archive, installed the signed update and relaunched; fixture settings/bookmark/history and Finder icon preserved. The installed Premiere Versions app was not touched.')
finally:
 if process is not None and process.poll() is None:process.terminate()
 if server:server.shutdown();server.server_close()
 print('Local fixture evidence:',fixture)
