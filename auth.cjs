'use strict';
const {randomBytes}=require('node:crypto');
function mode(c,env=process.env){if(env.PERSONAL_CONSOLE_AUTH==='verified-door')return 'verified-door';if(env.PERSONAL_CONSOLE_AUTH)throw Error('未知门禁模式');if(c.enableUserAccounts===true)return 'account';if(c.basicAuthMode===true)return 'basic-session';throw Error('未配置受支持的认证：需要原生账号、Basic Auth 或可信门禁');}
function identity(r,m){if(m==='verified-door'){const a=(r.headers.cookie||'').split(';').map(x=>x.trim()).filter(x=>x.startsWith('__Host-tavern='));const t=a.length===1?a[0].slice(14):'';return /^[A-Za-z0-9_-]{43}$/.test(t)?'door:'+t:null;}if(m==='account'){const h=r.user?.profile?.handle;return h&&r.session?.handle===h&&r.user.profile.enabled&&r.user.profile.password?'account:'+h:null;}if(m==='basic-session'&&r.user?.profile&&r.session&&r.headers.authorization?.startsWith('Basic ')){// Only called downstream of ST's active Basic middleware. Never use credentials as a log key.
 const session=r.session;if(!/^[a-f0-9]{64}$/.test(session.pcBrowserId||''))session.pcBrowserId=randomBytes(32).toString('hex');return 'basic:'+session.pcBrowserId;}return null;}
function inspect(cfg){const m=mode(cfg);console.log('Personal Console 认证模式:',m);return m;}
module.exports={mode,identity,inspect};
