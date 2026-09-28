#!/usr/bin/env python3
"""Build a verified offline update bundle from a completed rootfs and boot image."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

ap = argparse.ArgumentParser()
ap.add_argument('--rootfs', required=True)
ap.add_argument('--kernel', required=True)
ap.add_argument('--version', required=True)
ap.add_argument('--output', required=True)
ap.add_argument('--soc', choices=('sm8650', 'sm8550'), default='sm8650')
a = ap.parse_args()
# Device models (DTB `model`) each package may install on, and the Decky
# plugins it carries. KONKR Control is KONKR-only (it drives konkrd).
DEVICES = {'sm8650': ['KONKR Pocket FIT', 'AYANEO Pocket S2'],
           'sm8550': ['Retroid Pocket 6', 'Retroid Pocket 6 TOP-DPAD']}[a.soc]
PLUGINS = ('konkr-control', 'decky-lsfg-vk') if a.soc == 'sm8650' else ('decky-lsfg-vk',)
root = Path(a.rootfs).resolve(); output = Path(a.output).resolve()
if not (root / 'usr/lib/liblsfg-vk-layer-arm64.so').is_file(): raise SystemExit('missing LSFG v2 ARM layer')
with tempfile.TemporaryDirectory(prefix='konkr-package-', dir=output.parent) as temp:
    stage = Path(temp)
    def copy(src, dst):
        dst.mkdir(parents=True, exist_ok=True)
        # The completed build tree must remain unchanged throughout packaging.
        # Same-filesystem hard links retain exact metadata without another full copy.
        if src.stat().st_dev == dst.stat().st_dev:
            subprocess.run(['cp', '-a', '--link', str(src) + '/.', str(dst) + '/'], check=True)
        else:
            subprocess.run(['rsync', '-aHAX', '--numeric-ids', str(src) + '/', str(dst) + '/'], check=True)
    for rel in ('usr', 'opt', 'etc', 'var/lib/overlays/etc/upper'):
        src = root / rel
        if src.exists(): copy(src, stage / 'root' / rel)
    for name in PLUGINS:
        copy(root / 'home/steamos/homebrew/plugins' / name, stage / 'home/steamos/homebrew/plugins' / name)
    (stage / 'boot').mkdir()
    subprocess.run(['cp', a.kernel, str(stage / 'boot/KERNEL')], check=True)
    files = {}
    for p in sorted(stage.rglob('*')):
        if not p.is_file() or p.is_symlink(): continue
        h = hashlib.sha256()
        with p.open('rb') as f:
            for b in iter(lambda: f.read(4 << 20), b''): h.update(b)
        files[str(p.relative_to(stage))] = h.hexdigest()
    (stage / 'manifest.json').write_text(json.dumps({'format': 1, 'architecture': 'aarch64',
        'devices': DEVICES, 'version': a.version, 'files': files}, indent=2))
    subprocess.run(['tar', '--xattrs', '--acls', '--numeric-owner', '-czf', str(output) + '.part',
                    '-C', str(stage), 'manifest.json', 'root', 'home', 'boot'], check=True)
    os.replace(str(output) + '.part', output)
h = hashlib.sha256()
with output.open('rb') as f:
    for b in iter(lambda: f.read(4 << 20), b''): h.update(b)
output.with_name(output.name + '.sha256').write_text(h.hexdigest() + '  ' + output.name + '\n')
print(output, h.hexdigest())
