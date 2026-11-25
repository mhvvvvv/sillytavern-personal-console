'use strict';
const {randomBytes,createHmac,randomUUID}=require('node:crypto');
const info={id:'personal-console',name:'Personal Console',description:'Session-scoped HTTP diagnostics for chat completions'};
let stop;
async function init(router){
 if(stop)throw Error('already initialized');
 const salt=randomBytes(32),store=new Map();let active=true;
 const auth=require('./auth.cjs');let m;if(process.env.PERSONAL_CONSOLE_AUTH==='verified-door')m=auth.mode({});else{const {getConfig}=await import(require('node:url').pathToFileURL(require('node:path').resolve('src/util.js')).href);m=auth.mode(getConfig());if(m==='basic-session'&&!(globalThis.COMMAND_LINE_ARGS?.listen===true&&globalThis.COMMAND_LINE_ARGS?.basicAuthMode===true))throw Error('Basic Auth 中间件未实际启用，拒绝收集日志');}
 function key(r){const id=auth.identity(r,m);return id?createHmac('sha256',salt).update(id).digest('hex'):null;}
 const ttl=600000, slots=new WeakMap();
 function bucket(k){const b=store.get(k);if(!b)return;const alive=b.rows.filter(e=>e.pending||e.exp>Date.now());if(!alive.length){store.delete(k);return;}if(alive.length!==b.rows.length){b.rows=alive;b.rev=randomUUID();}return b;}
 function prune(){for(const k of store.keys())bucket(k);}
 function begin(r,s){if(!r.user?.profile)return;const k=key(r);if(!k)return;let b=bucket(k);if(!b){if(store.size>=256){prune();if(store.size>=256)store.delete(store.keys().next().value);}b={rows:[]};store.set(k,b);}
  const id=randomUUID(),ts=Date.now(),model=r.body?.model;
  const e={id,ts,model:typeof model==='string'&&/^[\w.:/-]{1,160}$/u.test(model)&&!/(?:sk-|AIza|eyJ)/.test(model)?model:null,pending:true,http:null,ms:null,kind:'pending',result:null,revision:0};
  b.rows.unshift(e);if(b.rows.length>5)b.rows.pop();b.rev=randomUUID();slots.set(r,{k,id});
  const current=()=>active&&store.get(k)===b&&b.rows.includes(e);let stream,finished=false;
  if(r.body?.stream===true){stream=require('./stream.cjs').observer();const write=s.write,end=s.end;function tap(chunk){try{if(!current()){stream=null;return;}if(stream&&s.statusCode<400)stream.push(chunk);}catch{}}s.write=function(chunk,...args){tap(chunk);return write.call(this,chunk,...args);};s.end=function(chunk,...args){tap(chunk);return end.call(this,chunk,...args);};}
  function finish(){if(finished)return;finished=true;if(!current())return;const ok=s.writableFinished;if(stream&&!e.result){e.result=stream.finish(ok);e.revision++;}e.http=s.statusCode;e.ms=Date.now()-ts;e.pending=false;e.exp=Date.now()+ttl;e.kind=e.result?.kind==='error'||e.http>=400?'error':!ok?'interrupted':e.result?.kind||'finished';b.rev=randomUUID();}s.once('finish',finish);s.once('close',finish);
 }
 const detach=await require('./errors.cjs').attach((r,text,kind='error')=>{const a=slots.get(r);if(!a)return;const b=store.get(a.k),e=b?.rows.find(x=>x.id===a.id);if(e){e.result={text,kind};e.revision++;e.kind=kind;b.rev=randomUUID();}},begin);
 router.get('/logs',(r,s)=>{s.set('Cache-Control','private, no-store');const k=r.user?.profile&&key(r);if(!k)return s.sendStatus(403);const b=bucket(k);if(r.query?.id!==undefined){const e=b?.rows.find(x=>x.id===r.query.id);return e?s.json({id:e.id,revision:e.revision,text:e.result?.text||null}):s.sendStatus(404);}
  const rev=b?.rev||'empty';if(r.query?.since===rev)return s.status(204).end();const rows=(b?.rows||[]).map(({result,exp,...summary})=>summary);return s.json({rev,pending:rows.some(x=>x.pending),rows});});
 const timer=setInterval(prune,60000);timer.unref();console.info('[personal-console] ready '+require('./package.json').version);stop=()=>{active=false;detach();clearInterval(timer);store.clear();stop=null;};
}
async function exit(){stop?.();}module.exports={info,init,exit};
