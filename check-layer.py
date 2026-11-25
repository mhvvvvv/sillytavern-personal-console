"""Read-only guard. Only trust bind mounts also present in the resolved Compose service."""
import json
import subprocess
import sys
from pathlib import PurePosixPath as Path


def unsafe(delta, app, trusted):
    parents = {p for mount in trusted for p in mount.parents}
    for line in delta.splitlines():
        op, sep, raw = line.partition(' ')
        if not sep or op not in ('A', 'C', 'D') or not raw.startswith('/'):
            raise ValueError('unrecognized docker diff output')
        path = Path(raw)
        if path != app and app not in path.parents:
            continue
        if op in ('A', 'C') and path in trusted:
            continue
        if op == 'C' and path in parents:
            continue
        return True
    return False


if __name__ == '__main__':
    cid, svc, root = sys.argv[1:]; app = Path(root)
    def read(*args):
        return subprocess.check_output(args, text=True)
    live = json.loads(read('docker','inspect','--format','{{json .Mounts}}',cid))
    vols = json.loads(read('docker','compose','config','--format','json'))['services'][svc].get('volumes',[])
    binds = {(v['source'],v['target']) for v in vols if v.get('type')=='bind'}
    trusted = {Path(m['Destination']) for m in live if m['Type']=='bind' and (m['Source'],m['Destination']) in binds}
    sys.exit(int(unsafe(read('docker','diff',cid),app,trusted)))
