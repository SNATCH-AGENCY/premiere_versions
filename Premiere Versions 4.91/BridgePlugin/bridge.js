/* Only this app's local endpoint and fixed host methods are used. No Node or remote network. */
(function(){
 const invoke=expression=>new Promise((resolve,reject)=>{
  window.__adobe_cep__.evalScript(expression,result=>{
   const parts=String(result).split('|');
   if(!['PV1','PV2'].includes(parts[0])||!['OK','CONFIG'].includes(parts[1]))return reject(Error(parts[2]||'Premiere host unavailable'));
   try{resolve(decodeURIComponent(parts[2]));}catch(_){reject(Error('Invalid project path'));}
  });
 });
 const ppro={Project:{getActiveProject:async()=>{
  const path=await invoke('$._PVBridge.inspect()');
  return {path,save:async()=>await invoke('$._PVBridge.save('+JSON.stringify(encodeURIComponent(path))+')')===path};
 }}};
 const handle=PVBridgeCore.createHandler(ppro);
 let socket,retry,delay=1000,stopped=false;
 function later(){if(!stopped){retry=setTimeout(connect,delay);delay=Math.min(delay*2,8000);}}
 async function connect(){
  if(stopped)return;clearTimeout(retry);
  try{
   const config=JSON.parse(await invoke('$._PVBridge.configuration()'));
   if(config.protocolVersion!==2||!Number.isInteger(config.port)||config.port<1024||config.port>65535||!/^[a-f0-9]{64}$/.test(config.credential))throw Error('Invalid local configuration');
   if(stopped)return;
   const ws=new WebSocket('ws://127.0.0.1:'+config.port);socket=ws;
   ws.onopen=()=>ws.send(JSON.stringify({type:'hello',protocol:2,token:config.credential,plugin:'dev.premiereversions.bridge',version:'4.91.1'}));
   ws.onmessage=async event=>{
    if(socket!==ws)return;
    try{const msg=JSON.parse(event.data);if(msg.type==='welcome'){delay=1000;return;}
     const result=await handle(msg);if(result&&socket===ws&&ws.readyState===1)ws.send(JSON.stringify(result));
    }catch(_){}
   };
   ws.onerror=()=>{};
   ws.onclose=()=>{if(socket!==ws)return;socket=null;later();};
  }catch(_){later();}
 }
 window.addEventListener('unload',()=>{stopped=true;clearTimeout(retry);if(socket)socket.close();});
 connect();
})();
