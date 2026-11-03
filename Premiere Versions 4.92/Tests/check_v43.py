from pathlib import Path
import subprocess,tempfile,shutil
root=Path(__file__).resolve().parents[1]
localization=(root/'Premiere Versions/Localization.swift').read_text()
controls=(root/'Premiere Versions/UtilityInteraction.swift').read_text()
gate=controls[controls.index('nonisolated struct PVEscapeGate'):controls.index('/// Intercepts Escape')]
uptime=controls[controls.index('nonisolated enum PVUptime'):controls.index('/// Embedded color')]
updates=(root/'Premiere Versions/Updates.swift').read_text().split('struct PVUpdateSettings: View')[0]
stub='nonisolated enum AppRelease { static let version="4.3"; static let build="1" }\n'
harness=r'''
nonisolated final class MockProtocol: URLProtocol {
 static var count = 0
 static var code = 200
 static var body = Data()
 override class func canInit(with request: URLRequest) -> Bool { true }
 override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
 override func startLoading() {
  Self.count += 1
  let response = HTTPURLResponse(url:request.url!,statusCode:Self.code,httpVersion:nil,headerFields:nil)!
  client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
  client?.urlProtocol(self,didLoad:Self.body)
  client?.urlProtocolDidFinishLoading(self)
 }
 override func stopLoading() {}
}
@main struct Checks {
 @MainActor static func main() async throws {
  func check(_ value:Bool,_ reason:String) { if !value { print("FAIL:",reason); exit(1) } }
  var gate=PVEscapeGate()
  check(gate.accept(time:1,repeated:false),"first Escape")
  check(!gate.accept(time:1.1,repeated:false),"double Escape debounce")
  check(!gate.accept(time:2,repeated:true),"held Escape")
  check(gate.accept(time:2,repeated:false),"later Escape")
  let zero=Date(timeIntervalSince1970:0)
  check(PVUptime.label(since:zero,now:zero)=="0 days 0 hours 0 minutes","zero uptime")
  check(PVUptime.label(since:zero,now:Date(timeIntervalSince1970:90060))=="1 day 1 hour 1 minute","singular uptime")
  check(PVUptime.label(since:zero,now:Date(timeIntervalSince1970:180120))=="2 days 2 hours 2 minutes","plural uptime")
  check(PVUptime.label(since:Date(timeIntervalSince1970:100),now:zero)=="0 days 0 hours 0 minutes","clock moved back")
  check(PVLocalization.text("Настройки",language:"en")=="Settings","English catalog")
  check(PVLocalization.text("Settings",language:"ru")=="Настройки","switching cached messages back to Russian")
  let personal="Монтаж_Настройки_v014.prproj"
  check(PVLocalization.text("Версия \(personal) сохранена",language:"en")=="Version \(personal) saved","user value preserved")
  check(PVLocalization.text("comment",language:"ru")=="comment","designer English preserved")
  check(PVLocalization.text("press return",language:"ru")=="press return","designer hint preserved")
  check(PVReleaseSource.permits(URL(string:"https://github.com/SNATCH-AGENCY/premiere_versions/releases/download/v4.91-build1/app.zip")!),"organization release trusted")
  check(PVReleaseSource.permits(URL(string:"https://github.com/pewakkk/premiere_versions/releases/download/v4.9-build1/app.zip")!),"legacy redirect retained")
  for value in ["https://github.com.evil.invalid/SNATCH-AGENCY/premiere_versions/releases/download/a.zip", "https://github.com/SNATCH-AGENCY/other/releases/download/a.zip", "https://github.com/SNATCH-AGENCY/premiere_versions/releases/download/v/../../../../other/a.zip", "https://user@github.com/SNATCH-AGENCY/premiere_versions/releases/download/a.zip"] {
   check(!PVReleaseSource.permits(URL(string:value)!),"untrusted migrated release rejected")
  }
  let xml="""
  <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
  <item><sparkle:version>4.3.2</sparkle:version><sparkle:shortVersionString>4.3</sparkle:shortVersionString><enclosure url="https://github.com/pewakkk/premiere_versions/releases/download/v4.3-2/app.zip"/></item>
  <item><sparkle:version>4.4.1</sparkle:version><sparkle:shortVersionString>4.4</sparkle:shortVersionString><enclosure url="https://github.com/SNATCH-AGENCY/premiere_versions/releases/download/v4.4/app.zip"/></item>
  <item><sparkle:version>99.1</sparkle:version><sparkle:shortVersionString>99</sparkle:shortVersionString><enclosure url="https://untrusted.invalid/app.zip"/></item>
  </channel></rss>
  """
  let items=try PVAppcastReader.parse(Data(xml.utf8))
  check(items.count==2,"untrusted enclosure rejected")
  check(items[0].build=="2","feed build extracted")
  check(PVReleaseOrder.newer(items[1],version:"4.3",build:"99"),"new minor beats larger old build")
  check(!PVReleaseOrder.newer(items[0],version:"4.3",build:"2"),"same build is not update")
  do { _=try PVAppcastReader.parse(Data("<html/>".utf8));check(false,"HTML must not count as appcast") } catch {}
  let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[MockProtocol.self]
  let session=URLSession(configuration:config)
  let name="pv43-checks-"+UUID().uuidString,defaults=UserDefaults(suiteName:name)!
  defer { defaults.removePersistentDomain(forName:name);session.invalidateAndCancel() }
  defaults.set("/custom/path",forKey:"archivePath");defaults.set("previous",forKey:"logoVariant")
  defaults.set("ru",forKey:"interfaceLanguage")
  let service=PVUpdateService(session:session,defaults:defaults)
  let automatic=PVUpdateService(session:session,defaults:defaults)
  MockProtocol.body=Data(xml.utf8)
  automatic.startAutomaticChecks();automatic.startAutomaticChecks()
  while automatic.checking { try await Task.sleep(nanoseconds:10_000_000) }
  check(MockProtocol.count==1,"automatic startup check is silent and starts only once")
  MockProtocol.count=0
  MockProtocol.body=Data(xml.utf8)
  service.check();service.check()
  while service.checking { try await Task.sleep(nanoseconds:10_000_000) }
  check(MockProtocol.count==1,"parallel check requests coalesced")
  check(service.available?.version=="4.4","newest release selected")
  check(service.lastCheck != nil,"real successful response sets last-check date")
  let previousDate=service.lastCheck
  MockProtocol.code=404
  service.check()
  while service.checking { try await Task.sleep(nanoseconds:10_000_000) }
  check(service.lastCheck==previousDate && service.available==nil,"404 never claims success or keeps stale update")
  MockProtocol.code=500
  service.check()
  while service.checking { try await Task.sleep(nanoseconds:10_000_000) }
  check(service.lastCheck==previousDate,"server error preserves previous successful check")
  check(defaults.string(forKey:"archivePath")=="/custom/path" && defaults.string(forKey:"logoVariant")=="previous" && defaults.string(forKey:"interfaceLanguage")=="ru","custom settings preserved")
  print("PASS: Escape debounce; uptime plurals; language switching and user content; appcast validation/version ordering; shared checks; truthful check timestamps and preserved settings")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='pv43-checks-') as tmp:
 p=Path(tmp);swift=p/'Checks.swift';swift.write_text(localization+'\n'+updates+'\n'+gate+uptime+stub+harness)
 shutil.copy(root/'Premiere Versions/Translations.json',p/'Translations.json')
 subprocess.run(['xcrun','swiftc','-parse-as-library','-swift-version','5','-module-cache-path',str(p/'modules'),str(swift),'-o',str(p/'Checks')],check=True)
 subprocess.run([str(p/'Checks')],check=True)
