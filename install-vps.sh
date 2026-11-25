#!/bin/sh
# Fresh install only. Never recreate, replace, or reconfigure the container.
set -eu
repo=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
fail(){ echo "停止：$*" >&2; exit 1; }
case "$#:${1:-}" in 0:|1:--dry-run);;*) fail '只支持 --dry-run';;esac
[ -z "${DOCKER_HOST:-}" ] || fail '要求本地 Docker';case $(docker context inspect --format '{{.Endpoints.docker.Host}}') in unix://*) ;;*)fail '要求本地 Docker';;esac
candidates=''; count=0; ids=$(docker ps -q --no-trunc) || fail '无法读取运行容器';for id in $ids;do if docker exec "$id" node -e 'const f=require("fs");process.exit(require("./package.json").name==="sillytavern"&&f.existsSync("src/plugin-loader.js")?0:1)' >/dev/null 2>&1;then count=$((count+1));candidates="$candidates $id";printf '%s) ' "$count";docker inspect -f '{{.Name}} ({{index .Config.Labels "com.docker.compose.service"}})' "$id";fi;done
[ "$count" -gt 0 ] || fail '未识别到正在运行的标准酒馆容器';n=1;if [ "$count" -gt 1 ];then [ -t 0 ] || fail '多实例需在终端选择';printf '请选择目标编号：';read -r n;case $n in ''|*[!0-9]*) fail '编号无效';;esac;[ "$n" -ge 1 ] && [ "$n" -le "$count" ] || fail '编号超出范围';fi
cid=$(printf '%s\n' $candidates | sed -n "${n}p");app=$(docker exec "$cid" pwd);case $app in /*) ;;*)fail '无法定位应用';;esac
cfg=$(docker exec -i "$cid" node - < "$repo/locate-config.cjs") || fail '无法确认当前配置文件';printf '使用配置：%s\n' "$cfg"
# The application and its data are trusted local directories. Reject existing entries, including dangling links.
docker exec -i "$cid" node -e 'const fs=require("fs"),Module=require("module"),cfg=require("yaml").parse(fs.readFileSync(process.argv[1],"utf8")),m=new Module("pc-mode");m._compile(fs.readFileSync(0,"utf8"),"pc-mode.cjs");m.exports.inspect(cfg)' "$cfg" < "$repo/auth.cjs"
docker exec "$cid" node -e 'const f=require("fs"),p=require("path"),c=require("yaml").parse(f.readFileSync(process.argv[1],"utf8"));if(c.enableServerPlugins!==true)throw Error("请审查现有插件并手动开启 enableServerPlugins");for(const d of ["plugins","public/scripts/extensions/third-party"]){if(f.realpathSync(d)!==p.resolve(d))throw Error("拒绝非标准链接目录");f.accessSync(d,f.constants.W_OK);}const dr=c.dataRoot||"data";for(const d of ["plugins/personal-console","public/scripts/extensions/third-party/personal-console",...f.readdirSync(dr,{withFileTypes:true}).filter(x=>x.isDirectory()).map(x=>p.join(dr,x.name,"extensions/personal-console"))])if(f.lstatSync(d,{throwIfNoEntry:false}))throw Error("已安装或存在冲突，不覆盖");' "$cfg";
for f in auth.cjs index.cjs stream.cjs errors.cjs package.json ui/manifest.json ui/panel-053.js;do [ -f "$repo/$f" ] || fail '安装包不完整';done
printf '目标 %.12s。仅安装两个插件目录并重启原容器，不改 Compose、账号或挂载。普通重启保留；以后外部重建可能丢失，需要重装。\n' "$cid"
[ "${1:-}" != --dry-run ] || exit 0
[ -t 0 ] || fail '需在交互终端确认';printf '重启将中断当前回复，继续？[y/N] ';read -r ans;case $ans in Y|y);;*)exit 0;;esac
back=$app/plugins/personal-console;ui=$app/public/scripts/extensions/third-party/personal-console
b=0;u=0;restart=0
cleanup(){ rc=$?;trap - EXIT; if [ "$rc" != 0 ];then echo '安装未通过，尝试只移除本次创建的目录' >&2; [ "$u" = 0 ] || docker exec "$cid" rm -r -- "$ui" || :; [ "$b" = 0 ] || docker exec "$cid" rm -r -- "$back" || :; [ "$restart" = 0 ] || docker restart "$cid" >/dev/null || :;fi;exit "$rc";};trap cleanup EXIT;trap 'exit 1' HUP INT TERM
# mkdir without -p refuses to overwrite an existing installation.
docker exec "$cid" mkdir "$back"; b=1;docker exec "$cid" mkdir "$ui";u=1
for f in auth.cjs index.cjs stream.cjs errors.cjs package.json;do docker cp "$repo/$f" "$cid:$back/$f";done
for f in manifest.json panel-053.js;do docker cp "$repo/ui/$f" "$cid:$ui/$f";done
docker exec "$cid" sh -ec 'node --check plugins/personal-console/index.cjs;node --check plugins/personal-console/stream.cjs;node --check plugins/personal-console/errors.cjs;node --check public/scripts/extensions/third-party/personal-console/panel-053.js';restart=1;docker restart "$cid" >/dev/null
for i in $(seq 1 60);do if docker exec "$cid" node -e 'let c=require("yaml").parse(require("fs").readFileSync(process.argv[1],"utf8"));fetch("http://127.0.0.1:"+(c.port||8000)+"/",{redirect:"manual",signal:AbortSignal.timeout(1500)}).then(r=>process.exit(r.status>=200&&r.status<500?0:1)).catch(()=>process.exit(1))' "$cfg" >/dev/null 2>&1;then echo '原容器已重启并响应；请登录后在「我的后台」验证。';exit 0;fi;sleep 1;done;fail '未确认酒馆恢复'
