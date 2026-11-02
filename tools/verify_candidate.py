"""Verify archive bytes against the build stage, then smoke-test that exact Lua.

python tools/verify_candidate.py dist/ForeverHearthstone-VERSION.zip
No archive is installed, extracted, or published.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--lua', default=os.environ.get('FH_LUA'))
    args = parser.parse_args()
    archive = args.archive.resolve()
    stage = archive.with_suffix('')
    lua = args.lua or shutil.which('luajit') or str(
        Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe')
    report = dict(archive=str(archive), passed=False)
    evidence = ROOT / 'dist/readiness'
    evidence.mkdir(parents=True, exist_ok=True)
    try:
        sha = hashlib.sha256()
        with archive.open('rb') as f:
            for block in iter(lambda: f.read(1024 * 1024), b''):
                sha.update(block)
        report['sha256'] = sha.hexdigest()
        with zipfile.ZipFile(archive) as z:
            names = z.namelist()
            if len(set(n.lower() for n in names)) != len(names):
                raise ValueError('duplicate/case-colliding ZIP entries')
            for name in names:
                parts = PurePosixPath(name).parts
                if not parts or parts[0] != 'ForeverHearthstone' or '..' in parts or '\\' in name:
                    raise ValueError(f'unsafe or unexpected ZIP path: {name}')
                local = stage.joinpath(*parts)
                if not local.is_file() or z.read(name) != local.read_bytes():
                    raise ValueError(f'archive/stage bytes differ: {name}')
            staged_names = {p.relative_to(stage).as_posix() for p in stage.rglob('*') if p.is_file()}
            if staged_names != set(names):
                raise ValueError('stage contains missing or extra files')
            report['verified_files'] = len(names)
        command = [lua, 'tools/package_smoke.lua', str(stage / 'ForeverHearthstone')]
        report['smoke_command'] = command
        with (evidence / 'candidate-smoke.log').open('w', encoding='utf-8') as log:
            result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=120)
        if result.returncode:
            raise ValueError(f'packaged smoke failed ({result.returncode}); see candidate-smoke.log')
        report['passed'] = True
    except (OSError, ValueError, zipfile.BadZipFile, subprocess.TimeoutExpired) as exc:
        report['error'] = str(exc)
    (evidence / 'candidate-verification.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
