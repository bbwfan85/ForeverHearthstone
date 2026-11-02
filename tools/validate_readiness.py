"""One-command offline release gate. No WoW sessions or network required.

python tools/validate_readiness.py
Artifacts and replay commands: dist/readiness/report.json and *.log.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--lua', default=os.environ.get('FH_LUA'))
    p.add_argument('--seeds', type=int, default=2)
    p.add_argument('--skip-visuals', action='store_true')
    p.add_argument('--render-python', default=os.environ.get('FH_RENDER_PYTHON',sys.executable),
                   help='Python with Pillow installed (defaults to this interpreter)')
    args = p.parse_args()
    if args.seeds < 1:
        p.error('--seeds must be positive')
    lua = args.lua or shutil.which('luajit')
    if not lua:
        candidate = Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
        if candidate.is_file():
            lua = str(candidate)
    if not lua:
        p.error('LuaJIT required; pass --lua PATH or set FH_LUA')
    out = ROOT / 'dist/readiness'
    out.mkdir(parents=True, exist_ok=True)
    results = []
    env = dict(os.environ, FH_PREVIEW_DIR=str(out / 'visuals'), PYTHONDONTWRITEBYTECODE='1')
    (out / 'visuals').mkdir(exist_ok=True)

    def run(name, command, timeout=1200):
        start = time.monotonic()
        try:
            with (out / (name + '.log')).open('w', encoding='utf-8') as log:
                code = subprocess.run(command, cwd=ROOT, env=env, stdout=log,
                                      stderr=subprocess.STDOUT, timeout=timeout).returncode
        except (OSError, subprocess.TimeoutExpired) as exc:
            code = -1
            with (out / (name + '.log')).open('a', encoding='utf-8') as log:
                log.write(str(exc))
        row = dict(name=name, passed=code == 0, seconds=round(time.monotonic()-start, 3),
                   exit_code=code, replay=command)
        results.append(row)
        print(f"{'PASS' if row['passed'] else 'FAIL'} {name} ({row['seconds']}s)", flush=True)
        (out / 'report.json').write_text(json.dumps(results, indent=2), encoding='utf-8')

    for line in (ROOT / 'tools/vendor/SHA256SUMS').read_text().splitlines():
        digest, name = line.split(maxsplit=1)
        path = ROOT / 'tools/vendor' / name.lstrip('*')
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise SystemExit(f'Vendored data checksum failed: {path}')
    run('import', [sys.executable, 'tools/import_cards.py'])
    run('compile', [sys.executable, 'tools/compile_effects.py'])
    run('compiler-tests', [sys.executable, 'tools/test_compiler.py'])
    run('regressions', [lua, 'tests/run.lua'])
    for seed in range(1, args.seeds + 1):
        for fault in ('clean', 'latency', 'duplicate', 'loss', 'reload', 'disconnect', 'pause', 'incompatible', 'concede', 'mixed', 'terminal-loss'):
            name = f'duel-{seed}-{fault}'
            run(name, [lua, 'tools/duel_lab.lua', str(seed), fault, str((seed-1)%5+1),
                       str(out / (name + '-trace.log'))])
    for difficulty in range(1, 6):
        run(f'bot-matchups-{difficulty}', [lua, 'tools/bot_bench.lua', str(difficulty),
                                          str(difficulty), '4', str(difficulty), '0'])
    if not args.skip_visuals:
        run('visual-export', [lua, 'tools/collection_preview.lua'])
        scenes = ['x-hearth-narrow', 'x-collection-ultrawide', 'x-decks-narrow',
                  'x-pack-reveal-ultrawide', 'board-states', 'match-targeting', 'deck-wide', 'settings', 'board-live-hover']
        run('visual-render', [args.render_python, 'tools/collection_preview.py'] + scenes)
    print(f'Report: {out / "report.json"}')
    return int(any(not row['passed'] for row in results))


if __name__ == '__main__':
    sys.exit(main())
