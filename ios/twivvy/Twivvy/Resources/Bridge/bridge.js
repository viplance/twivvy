// Bundled protocol adapter only: no web UI, remote scripts, camera or microphone.
const emit = (type, data = {}) => window.webkit.messageHandlers.event.postMessage({ type, ...data });
async function nativeFetch(path, options = {}) {
  const result = await window.webkit.messageHandlers.request.postMessage({path, method:options.method || 'GET', body:options.body || null});
  return {ok:result.status>=200&&result.status<300,status:result.status,json:async()=>JSON.parse(result.body)};
}
// Native hashing also works when WebKit's file origin has no SubtleCrypto.
sha256Hex = text => window.webkit.messageHandlers.digest.postMessage(text);
Connection.prototype._save = function() {
  if (!this.code || !this.token) return;
  const saved = {code:this.code,token:this.token,role:this.role,seed:this.seed,map:this.map,myName:this.myName,peerName:this.peerName,game:this._game,savedAt:Date.now()};
  // Timer-only updates persist once per second; changed choices/proofs persist immediately.
  const fingerprint = JSON.stringify({...saved,savedAt:0,game:this._game ? {...this._game,savedAt:0,round:{...this._game.round,remaining:Math.ceil(this._game.round.remaining/1000)}} : null});
  if (fingerprint === this._lastNativeSave) return;
  this._lastNativeSave = fingerprint;
  // Preserve property order: existing browser peers compare serialized replay logs.
  emit('save', {savedJSON:JSON.stringify(saved)});
};
let connection, session, matchmaker;
let rematch = {mine:false,theirs:false,map:null};
const state = () => ({match:session?.match,selection:session?.round.selection,side:session?.side,peerName:connection?.peerName,remaining:session?.remaining()/1000});
function begin(saved) {
  session?.dispose();
  session = new MatchSession(connection, {
    saved,
    lock:()=>emit('lock'),
    active:active=>emit('active',{...state(),active}),
    paused:()=>emit('paused',state()),
    timer:fraction=>emit('timer',{remaining:fraction*30}),
    restore:()=>emit('restore',state()),
    resolved:async(event,before,after)=>{emit('resolved',{event,before,match:after});await new Promise(resolve=>setTimeout(resolve,1200));},
    finished:reason=>emit('finished',{...state(),reason})
  });
  emit('started',state());
}
function newConnection() {
  const c = new Connection(); connection = c;
  const on = (type,callback) => c.addEventListener(type,event=>{if(connection===c)callback(event.detail);});
  on('open',()=>{if(!session)begin();session.connected();emit('peer',{name:c.peerName});});
  on('peername',data=>emit('peer',data));
  on('peerlost',data=>{session?.pause(data.since);emit('paused');});
  on('guestjoined',()=>emit('status',{key:'status.peerFound'}));
  on('expired',()=>{session?.finish('expired');emit('error',{key:'error.peerAbsent'});});
  on('message',msg=>{
    if(msg.type!=='rematch' || !session?.ended) return;
    rematch.theirs=true;
    if(c.role==='guest' && Number.isInteger(msg.map) && msg.map>=0 && msg.map<3)rematch.map=msg.map;
    else if(c.role==='host' && rematch.mine)c.send({type:'rematch',map:rematch.map});
    emit('rematch',{requested:true}); maybeRematch();
  });
  return c;
}
function maybeRematch() {
  if(!rematch.mine||!rematch.theirs||rematch.map===null)return;
  connection.map=rematch.map;rematch={mine:false,theirs:false,map:null};begin();session.connected();
}
function close() {
  session?.dispose(); session=null;
  connection?.close();connection=null;
  matchmaker?.close();matchmaker=null;
  rematch={mine:false,theirs:false,map:null};emit('clearSave');
}
window.nativeCommand = async function(message) {
 try {
  switch(message.action) {
   case 'host': {
    close();const c=newConnection();
    const code=await c.host({map:Math.floor(Math.random()*3),seed:crypto.getRandomValues(new Uint32Array(1))[0],name:message.name});
    if(connection===c)emit('room',{code});break;
   }
   case 'join': close();await newConnection().join(message.code,{name:message.name});emit('room',{code:message.code});break;
   case 'online': {
    close();const m=new Matchmaker();matchmaker=m;
    m.addEventListener('count',e=>emit('count',e.detail));
    m.addEventListener('error',()=>emit('status',{key:'status.queueRetry'}));
    m.addEventListener('matched',async e=>{if(matchmaker!==m)return;try{await newConnection().acceptMatch(e.detail);emit('room',{code:connection.code});}catch{emit('error',{key:'error.matchConnect'});}});
    await m.join(message.name);break;
   }
   case 'resume': { const saved=JSON.parse(message.savedJSON); close();newConnection();await connection.resume(saved);if(saved.game)begin(saved.game);emit('room',{code:connection.code});break; }
   case 'choose': session?.choose(message.command ? {platform:message.command.platform,dir:message.command.dir} : null);break;
   case 'suspend': connection?.suspend();break;
   case 'foreground': if(connection)connection.reconnect();break;
   case 'rematch':
    if(!session?.ended||connection?.channel?.readyState!=='open'){emit('error',{key:'status.peerDisconnected'});break;}
    rematch.mine=true;if(connection.role==='host')rematch.map=Math.floor(Math.random()*3);
    connection.send({type:'rematch',map:rematch.map});maybeRematch();break;
   case 'count': emit('count',{online:await onlinePlayerCount()});break;
   case 'leave': close();break;
  }
 } catch(error) {
  const key=error.status===404||error.status===410?'error.notFound':error.status===409?'error.occupied':error.status===426?'error.oldVersion':'error.connectFailed';
  emit('error',{key});
 }
};
emit('ready');
