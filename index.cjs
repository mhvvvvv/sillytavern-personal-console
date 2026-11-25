'use strict';
const {randomBytes,createHmac,randomUUID}=require('node:crypto');
const info={id:'personal-console',name:'Personal Console',description:'Session-scoped HTTP diagnostics for chat completions'};
let stop;
async function init(router){
 if(stop)throw Error('already initialized');
 const salt=randomBytes(32),store=new Map();let active=true;
 const auth=require('./auth.cjs');let m;if(process.env.PERSONAL_CONSOLE_AUTH==='verified-door')m=auth.mode({});else{const {getConfig}=await import(require('node:url').pathToFileURL(require('node:path').resolve('src/util.js')).href);m=auth.mode(getConfig());if(m==='basic-session'&&!(globalThis.COMMAND_LINE_ARGS?.listen===true&&globalThis.COMMAND_LINE_ARGS?.basicAuthMode===true))throw Error('Basic Auth 中间件未实际启用，拒绝收集日志');}
 function key(r){const id=auth.identity(r,m);return id?createHmac('sha256',salt).update(id).digest('hex'):null;}
 function prune(){const now=Date.now();for(const [k,v] of store)if(v.exp<=now)store.delete(k);}
 const slots=new WeakMap();
 function begin(r,s){if(!r.user?.profile)return;const k=key(r);if(!k)return;if(!store.has(k)&&store.size>=256){prune();if(store.size>=256)store.delete(store.keys().next().value);}const ts=Date.now(),id=randomUUID().slice(0,8),v={rev:randomUUID(),pending:true,exp:ts+600000,lines:[`[${id}] 请求中…`],lastResult:null};store.set(k,v);slots.set(r,{k,id,ref:new WeakRef(v)});let stream=null,finished=false;if(r.body?.stream===true){stream=require('./stream.cjs').observer();const write=s.write,end=s.end;function tap(chunk){try{if(!active||store.get(k)!==v){stream=null;return;}if(stream&&s.statusCode<400)stream.push(chunk);}catch{}}s.write=function(chunk,...args){tap(chunk);return write.call(this,chunk,...args);};s.end=function(chunk,...args){tap(chunk);return end.call(this,chunk,...args);};}function finish(){if(finished)return;finished=true;if(!active||store.get(k)!==v)return;if(stream&&!v.lastResult){const x=stream.finish(s.writableFinished);v.lastResult={id,...x};}v.lines=[`[${id}] ${s.writableFinished?'HTTP '+s.statusCode:'connection closed before finish'} (${Date.now()-ts} ms)`];v.pending=false;v.rev=randomUUID();v.exp=Date.now()+600000;}s.once('finish',finish);s.once('close',finish);}
 const detach=await require('./errors.cjs').attach((r,text,kind='error')=>{const a=slots.get(r);if(!a)return;const v=store.get(a.k);if(v&&v===a.ref.deref()){v.lastResult={id:a.id,text,kind};v.rev=randomUUID();}},begin);
 router.get('/logs',(r,s)=>{s.set('Cache-Control','private, no-store');const k=r.user?.profile&&key(r);if(!k)return s.sendStatus(403);let v=store.get(k);if(v&&v.exp<=Date.now()){store.delete(k);v=null;}const rev=v?.rev||'empty';if(r.query?.since===rev)return s.status(204).end();return s.json({rev,pending:v?.pending||false,lines:v?.lines||[],lastResult:v?.lastResult||null});});
 const timer=setInterval(prune,60000);timer.unref();console.info('[personal-console] ready '+require('./package.json').version);stop=()=>{active=false;detach();clearInterval(timer);store.clear();stop=null;};
}
async function exit(){stop?.();}module.exports={info,init,exit};
