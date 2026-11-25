const host=document.querySelector('#extensions_settings');if(host&&!document.querySelector('#pc-standard')){const box=document.createElement('div');box.id='pc-standard';box.className='inline-drawer';box.innerHTML='<div class="inline-drawer-toggle inline-drawer-header" role="button" tabindex="0" aria-expanded="false"><b>我的后台</b><div class="inline-drawer-icon fa-solid fa-circle-chevron-down down"></div></div><div class="inline-drawer-content"><p></p><pre style="max-height:45vh;overflow:auto;white-space:pre-wrap;overflow-wrap:anywhere"></pre></div>';const head=box.firstElementChild,icon=head.lastElementChild,status=box.querySelector('p'),out=box.querySelector('pre');const err=document.createElement('pre'),copy=document.createElement('button');err.style.cssText=out.style.cssText;copy.type='button';copy.textContent='复制最近一次返回';copy.hidden=true;out.after(copy,err);copy.onclick=async()=>{try{await navigator.clipboard.writeText(err.textContent);copy.textContent='已复制';}catch{copy.textContent='请长按下方原文复制';}};host.prepend(box);let timer,epoch=0,controller,rev='',pending=false,delay=3000;
 const visible=()=>!document.hidden&&icon.classList.contains('up');
 function clear(){rev='';pending=false;delay=3000;out.textContent='';err.textContent='';copy.hidden=true;copy.title='';copy.textContent='复制最近一次返回';}
 async function read(n){if(n!==epoch||!visible())return;controller=new AbortController();try{
  const r=await fetch('/api/plugins/personal-console/logs'+(rev?'?since='+encodeURIComponent(rev):''),{signal:controller.signal,cache:'no-store',redirect:'error'});
  if(n!==epoch)return;
  if(r.status===204){delay=pending?3000:Math.min(delay*2,15000);return;}
  if(!r.ok)throw Error();const j=await r.json();if(n!==epoch)return;
  rev=j.rev||'';pending=j.pending===true;delay=3000;
  status.textContent=j.lines.length?'当前登录会话 · 请求诊断':'已连接 · 等待本浏览器的聊天补全请求';
  err.textContent=j.lastResult?.text||'';copy.hidden=!err.textContent;copy.title=j.lastResult?.id||'';copy.textContent='复制最近一次返回';out.textContent=j.lines.join('\n');out.scrollTop=out.scrollHeight;
 }catch{if(n===epoch){clear();status.textContent='未连接，请检查登录状态';delay=6000;}}
 finally{if(n===epoch&&visible())timer=setTimeout(()=>read(n),delay);}}
 function sync(){head.setAttribute('aria-expanded',String(icon.classList.contains('up')));epoch++;clearTimeout(timer);controller?.abort();clear();if(visible()){status.textContent='连接中…';read(epoch);}}
 new MutationObserver(sync).observe(icon,{attributes:true,attributeFilter:['class']});document.addEventListener('visibilitychange',sync);head.onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();head.click();}};}
