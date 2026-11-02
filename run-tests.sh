#!/usr/bin/env bash
# Full verification: re-import printed data, recompile effects, run the engine
# tests. Any step failing fails the whole run.
#
# LuaJIT 2.1 (Lua 5.1 semantics -- the same language version WoW ships).
set -euo pipefail
cd "$(dirname "$0")"
# winget installs LuaJIT under the user's LOCALAPPDATA, which is not on PATH in
# a fresh Git Bash shell. Add it if we can find it; fall back to whatever is
# already on PATH.
for d in "${LOCALAPPDATA:-}/Programs/LuaJIT/bin" "$HOME/AppData/Local/Programs/LuaJIT/bin"; do
  [ -x "$d/luajit.exe" ] && export PATH="$PATH:$d" && break
done
command -v luajit >/dev/null || { echo "luajit not found -- winget install DEVCOM.LuaJIT"; exit 127; }

echo "==> verifying vendored data integrity"
( cd tools/vendor && sha256sum -c SHA256SUMS )

# Stale bytecode can make the tool scripts test a previous version of themselves.
rm -rf tools/__pycache__

echo "==> importing printed card data"
python tools/import_cards.py

echo "==> compiling effect scripts"
python tools/compile_effects.py

echo "==> compiler tests"
python tools/test_compiler.py

echo "==> running engine tests"
luajit tests/run.lua "$@"

# Opt-in: the Fireplace differential test (docs/33-FIREPLACE-ORACLE.md). Off by
# default because it needs a local venv the repo does not ship; tools/oracle/
# setup.sh builds it. ORACLE=1 ./run-tests.sh fails on any unexplained difference.
if [ "${ORACLE:-}" = 1 ]; then
  echo "==> Fireplace oracle"
  "$HOME/.cache/forever-hearthstone-oracle/venv/Scripts/python.exe" tools/oracle/oracle.py
fi
