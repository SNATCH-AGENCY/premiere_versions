/* Narrow host surface: inspect and save the selected existing project only. */
$._PVBridge = {
 configuration: function () {
  var file = new File(Folder.userData.fsName + "/Premiere Versions/Bridge/connection.json");
  try {
   if (!file.exists || file.length > 1024 || !file.open("r")) return "PV2|ERROR|Connection unavailable";
   file.encoding="UTF-8";var data=file.read();file.close();
   return "PV2|CONFIG|"+encodeURIComponent(data);
  }catch(e){try{file.close();}catch(_){}return "PV2|ERROR|Connection unavailable";}
 },
 inspect: function () {
  try { if (!app.project || !app.project.path) return "PV1|ERROR|No saved project open";
    return "PV1|OK|" + encodeURIComponent(app.project.path);
  } catch(e) { return "PV1|ERROR|Cannot inspect project"; }
 },
 save: function (encodedExpected) {
  try {
   var expected=decodeURIComponent(encodedExpected);
   if (!app.project || !app.project.path || app.project.path !== expected) return "PV1|ERROR|Active project changed";
   var before=new File(expected); if(!before.exists) return "PV1|ERROR|Project file is missing";
   var result=app.project.save();
   if(result !== 0 && result !== true) return "PV1|ERROR|Premiere save result: " + typeof result + " " + String(result);
   if(!app.project || app.project.path !== expected) return "PV1|ERROR|Active project changed while saving";
   var after=new File(expected);if(!after.exists || after.length <= 0) return "PV1|ERROR|Saved file unavailable";
   return "PV1|OK|"+encodeURIComponent(expected);
  } catch(e) {return "PV1|ERROR|Premiere save failed";}
 }
};
try { app.setExtensionPersistent("dev.premiereversions.bridge", 1); } catch(e) {}
