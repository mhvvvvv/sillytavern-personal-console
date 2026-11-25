"""Fresh install or upgrade an unmodified, non-mounted Docker install."""
import hashlib,json,os,pathlib,subprocess,sys,tempfile,time
P=pathlib.Path; repo=P(__file__).resolve().parent; cid,app,cfg=sys.argv[1:4]
known=json.loads((repo/'managed-files.json').read_text()); target=json.loads((repo/'package.json').read_text())['version']; paths=[app+'/plugins/personal-console',app+'/public/scripts/extensions/third-party/personal-console']
def run(*a):return subprocess.check_output(a,text=True).strip()
def ex(*a):return run('docker','exec',cid,*a)
def inspect():return json.loads(run('docker','inspect',cid))[0]
def state():
    js='''const f=require('fs'),p=require('path'),c=require('crypto'),o={};for(const [i,d] of process.argv.slice(1).entries()){if(!f.lstatSync(d,{throwIfNoEntry:false}))continue;if(f.realpathSync(d)!==d||!f.statSync(d).isDirectory())throw Error('unknown layout');o['dir'+i]=true;for(const n of f.readdirSync(d)){if(!['index.cjs','errors.cjs','stream.cjs','auth.cjs','package.json','manifest.json','panel-053.js'].includes(n))throw Error('extra file');const x=p.join(d,n),s=f.lstatSync(x);if(!s.isFile()||s.size>1048576)throw Error('unexpected file');o[(i?'ui/':'')+n]=c.createHash('sha256').update(f.readFileSync(x)).digest('hex')}}console.log(JSON.stringify(o))'''; v=json.loads(ex('node','-e',js,*paths));
    if not v:return None
    if not(v.pop('dir0',False) and v.pop('dir1',False)):raise ValueError('前后端不完整')
    for version,hashes in known.items():
        if hashes==v:return version
    raise ValueError('文件不是已知的未修改发行版本，拒绝覆盖')
def verify(version,marker):
    js="const c=require('yaml').parse(require('fs').readFileSync(process.argv[1],'utf8'));fetch('http://127.0.0.1:'+(c.port||8000)+'/',{redirect:'manual',signal:AbortSignal.timeout(1500)}).then(r=>process.exit([200,301,302,303,307,308,401,403].includes(r.status)?0:1)).catch(()=>process.exit(1))"
    for _ in range(40):
        if subprocess.run(['docker','exec',cid,'node','-e',js,cfg],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0 and state()==version:
            if not marker:return
            proc=subprocess.Popen(['docker','logs','--since',inspect()['State']['StartedAt'],cid],stdout=subprocess.PIPE,stderr=subprocess.STDOUT);ok=any(line.rstrip().endswith(('[personal-console] ready '+version).encode()) for line in proc.stdout);proc.stdout.close();proc.wait()
            if ok:return
        time.sleep(1)
    raise RuntimeError('酒馆响应或插件初始化验证失败')
def manage():
    for mount in inspect()['Mounts']:
        m=P(mount['Destination']);
        if any(m==P(p) or m in P(p).parents or P(p) in m.parents for p in paths):raise ValueError('插件涉及持久化挂载，请按原部署方式维护')
    old=state();files=known[target];
    if not all(hashlib.sha256((repo/f).read_bytes()).hexdigest()==h for f,h in files.items()):raise ValueError('安装包校验失败')
    print(f'目标 {cid[:12]}：{old or "未安装"} → {target}',flush=True)
    if old==target:print('已是最新版，未修改、未重启');return
    if old and tuple(map(int,old.split('.')))>=tuple(map(int,target.split('.'))):raise ValueError('拒绝降级')
    if sys.argv[4:]==['--dry-run']:print('预检通过；未修改、未重启');return
    if not sys.stdin.isatty() or input('将安装或备份升级，然后重启原容器，中断当前回复。继续？[y/N] ').strip().lower()!='y':return
    lock='/tmp/personal-console-install.lock';ex('mkdir',lock)
    try:
        if state()!=old:raise ValueError('确认后状态已变')
        if old:
            os.umask(0o077);base=P.home()/'.local/state/personal-console/backups';base.mkdir(parents=True,exist_ok=True);backup=P(tempfile.mkdtemp(dir=base,prefix=old+'-'));print('备份：',backup,flush=True)
            for i,p in enumerate(paths):run('docker','cp',cid+':'+p,str(backup/['backend','ui'][i]))
            for f,h in known[old].items():
                if hashlib.sha256((backup/('ui' if f.startswith('ui/') else 'backend')/P(f).name).read_bytes()).hexdigest()!=h:raise ValueError('备份验证失败')
        tmp=ex('mktemp','-d','/tmp/pc-upgrade.XXXXXX'); moved=[];placed=[];restarted=False
        try:
            for i in range(2):ex('mkdir',tmp+'/new'+str(i));ex('chmod','755',tmp+'/new'+str(i))
            for f in files:run('docker','cp',str(repo/f),cid+':'+tmp+'/new'+str(int(f.startswith('ui/')))+'/'+P(f).name)
            if state()!=old:raise ValueError('文件已变化')
            for i,p in enumerate(paths):
                if old:ex('mv',p,tmp+'/old'+str(i));moved.append(i)
                ex('mv',tmp+'/new'+str(i),p);placed.append(i)
            if state()!=target:raise ValueError('替换校验失败')
            restarted=True;run('docker','restart',cid);verify(target,True)
        except (Exception,KeyboardInterrupt):
            print('验证失败，正在恢复。暂存目录：',tmp,file=sys.stderr)
            if not inspect()['State']['Running']:run('docker','start',cid)
            for i in reversed(placed):ex('mv',paths[i],tmp+'/failed'+str(i))
            for i in moved:ex('mv',tmp+'/old'+str(i),paths[i]);
            if restarted:run('docker','restart',cid)
            verify(old,False);print('已验证恢复前后端文件和酒馆响应',file=sys.stderr);raise
        ex('rm','-rf','--',tmp);print('前后端版本、插件初始化和酒馆响应已验证；刷新页面即可。')
    finally:ex('rmdir',lock)
try:manage()
except Exception as e:sys.exit('停止：'+str(e))
