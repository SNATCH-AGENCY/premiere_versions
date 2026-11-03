/* Host-independent protocol logic: fail closed before archiving. */
(function (root) {
  const pathKey = p => typeof p === 'string' ? p.normalize('NFC') : '';
  function createHandler(ppro) {
    let busy = false;
    const seen = new Set();
    return async function handle(message) {
      const id = message && message.id;
      if (!message || message.type !== 'request' || !/^[a-f0-9-]{36}$/i.test(id || '') ||
          !['save', 'inspect'].includes(message.op)) return null;
      const reply = (ok, rest) => ({type:'result',id,ok,...rest});
      if (seen.has(id)) return reply(false,{error:'Duplicate request'});
      seen.add(id); if (seen.size > 256) seen.delete(seen.values().next().value);
      if (busy) return reply(false,{error:'Premiere save already in progress'});
      busy = true;
      try {
        const project = await ppro.Project.getActiveProject();
        const path = project && project.path;
        if (!path || !path.startsWith('/') || !/\.prproj$/i.test(path)) throw Error('Open and save a Premiere project first');
        if (message.op === 'inspect') return reply(true,{path});
        if (!message.expectedPath || pathKey(path) !== pathKey(message.expectedPath)) throw Error('Active Premiere project does not match the selected project');
        if (await project.save() !== true) throw Error('Premiere did not confirm saving');
        const after = await ppro.Project.getActiveProject();
        if (!after || pathKey(after.path) !== pathKey(path) || (project.guid && after.guid !== project.guid))
          throw Error('Active project changed while saving');
        return reply(true,{path:after.path});
      } catch (error) { return reply(false,{error:String(error.message || error).slice(0,300)}); }
      finally { busy = false; }
    };
  }
  if (typeof module !== 'undefined') module.exports = {createHandler};
  root.PVBridgeCore = {createHandler};
})(typeof globalThis !== 'undefined' ? globalThis : this);
