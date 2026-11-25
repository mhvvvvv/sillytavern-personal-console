#!/bin/sh
# Host-side installer. Run FROM the target checkout or Compose project.
set -eu
src=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P); root=$(pwd -P)
usage(){ echo 'Usage: sh /path/vps-install.sh native [--dry-run] [--enable-server-plugins] | compose SERVICE [--dry-run]' >&2; exit 2; }
case ${1:-} in native) shift; exec node "$src/install.cjs" "$@";; compose) shift;; *) usage;; esac
svc=${1:-}; case $svc in ''|[!a-zA-Z0-9]*|*[!a-zA-Z0-9_.-]*) usage;; esac; shift
dry=0; case $# in 0);;1) [ "$1" = --dry-run ] || usage;dry=1;;*)usage;;esac
fail(){ echo "STOP: $*" >&2; exit 1; }
[ -z "${DOCKER_HOST:-}${COMPOSE_FILE:-}" ] || fail 'Remote Docker / custom Compose chains: follow AGENTS.md.'
endpoint=$(docker context inspect --format '{{.Endpoints.docker.Host}}'); case $endpoint in unix://*) ;; *) fail 'Require a local Unix Docker socket';; esac
base=''; for f in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do if [ -f "$f" ]; then [ -z "$base" ] || fail 'Ambiguous base file';base=$f;fi;done; [ -n "$base" ] || fail 'No Compose base file in current directory';
id=$(docker compose ps -q "$svc"); [ "$(printf '%s' "$id" | wc -c)" -ge 12 ] || fail 'Target service is not running';
[ "$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "$id")" = "$root" ] || fail 'Wrong Compose project directory'; files=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.config_files"}}' "$id"); [ "$files" = "$root/$base" ] || fail 'Existing overrides/custom stack; preserve full file chain, see AGENTS.md'; project=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$id");case "$project" in ''|*[!a-zA-Z0-9_.-]*) fail 'Unexpected project name';;esac
app=$(docker exec "$id" node -e 'if(require("./package.json").name!=="sillytavern"||!require("fs").existsSync("src/plugin-loader.js"))process.exit(1);process.stdout.write(process.cwd())');case $app in /*) ;;*)fail 'Unknown app directory';;esac;case $app in *[!a-zA-Z0-9_./-]*)fail 'Nonstandard app path';;esac
# Read only explicit booleans, never dump settings or environment.
docker exec "$id" node -e 'const fs=require("fs"),p=require("path"),y=require("yaml"),c=y.parse(fs.readFileSync("config/config.yaml","utf8"));if(c.enableServerPlugins!==true){console.error("Enable server plugins in persistent config after reviewing other plugins, then retry.");process.exit(1)};if(!c.enableUserAccounts)console.error("NOTE: native account mode requires enabled password accounts; shared Basic Auth alone is insufficient.");const dr=c.dataRoot||"data";for(const f of ["plugins/personal-console","public/scripts/extensions/third-party/personal-console",...fs.readdirSync(dr,{withFileTypes:true}).filter(x=>x.isDirectory()).map(x=>p.join(dr,x.name,"extensions/personal-console"))])if(fs.existsSync(f)){console.error("Existing installation: stop; use reviewed upgrade path.");process.exit(1)}';
dest=personal-console-install; [ ! -e "$dest" ] && [ ! -L "$dest" ] || fail 'Staging target already exists'; echo "PLAN project=$project service=$svc app=$app; two read-only plugin mounts; no changes to ports, credentials, base Compose or running container"; [ "$dry" = 0 ] || exit 0
# Relative bind paths are resolved against the FIRST (-f base) project file.
mkdir "$dest"; trap 'rm -rf -- "$dest"' EXIT; mkdir "$dest/backend" "$dest/frontend"; for f in index.cjs errors.cjs stream.cjs package.json; do cp "$src/$f" "$dest/backend/"; done; cp "$src/ui/manifest.json" "$src/ui/panel-053.js" "$dest/frontend/";
ov=$dest/plugin.compose.yaml; printf 'services:\n  %s:\n    volumes:\n      - "./%s/backend:%s/plugins/personal-console:ro,Z"\n      - "./%s/frontend:%s/public/scripts/extensions/third-party/personal-console:ro,Z"\n' "$svc" "$dest" "$app" "$dest" "$app" > "$ov"; docker compose -p "$project" -f "$base" -f "$ov" config -q; trap - EXIT
printf 'Staged, NOT live. After backup and maintenance approval, activate with:\ndocker compose -p %s -f %s -f %s up -d --no-deps %s\nRollback: docker compose -p %s -f %s up -d --no-deps %s\n' "$project" "$base" "$ov" "$svc" "$project" "$base" "$svc"
