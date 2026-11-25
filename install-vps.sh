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
docker exec "$cid" node -e 'const f=require("fs"),p=require("path"),c=require("yaml").parse(f.readFileSync(process.argv[1],"utf8"));if(c.enableServerPlugins!==true)throw Error("请审查现有插件并手动开启 enableServerPlugins");for(const d of ["plugins","public/scripts/extensions/third-party"]){if(f.realpathSync(d)!==p.resolve(d))throw Error("拒绝非标准链接目录");f.accessSync(d,f.constants.W_OK);}const dr=c.dataRoot||"data";for(const d of [...f.readdirSync(dr,{withFileTypes:true}).filter(x=>x.isDirectory()).map(x=>p.join(dr,x.name,"extensions/personal-console"))])if(f.lstatSync(d,{throwIfNoEntry:false}))throw Error("已安装或存在冲突，不覆盖");' "$cfg";
exec python3 "$repo/manage-vps.py" "$cid" "$app" "$cfg" "$@"
