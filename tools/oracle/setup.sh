#!/usr/bin/env bash
# One-time setup for the Fireplace oracle (docs/33-FIREPLACE-ORACLE.md).
#
# Everything goes under ~/.cache/forever-hearthstone-oracle -- outside the repo,
# so nothing here can end up in a release. Fireplace is AGPL; it is only ever
# run locally, never shipped or linked into the addon.
#
# Needs Python 3.10+ (Fireplace's floor) and git-lfs (its CardDefs.xml is LFS).
#   winget install -e --id Python.Python.3.12
set -euo pipefail

ORACLE="$HOME/.cache/forever-hearthstone-oracle"
# Pinned so a Fireplace change cannot silently move the results.
FIREPLACE_COMMIT=47a2572a000db66645bb74a425a090d51f1004fa

PY=""
for cand in "${LOCALAPPDATA:-}/Programs/Python/Python312/python.exe" \
            "${LOCALAPPDATA:-}/Programs/Python/Python313/python.exe" \
            "$(command -v python3.12 || true)"; do
  [ -n "$cand" ] && [ -x "$cand" ] && PY="$cand" && break
done
[ -n "$PY" ] || { echo "Python 3.10+ not found -- winget install -e --id Python.Python.3.12"; exit 1; }

mkdir -p "$ORACLE"
if [ ! -d "$ORACLE/fireplace" ]; then
  git clone https://github.com/jleclanche/fireplace.git "$ORACLE/fireplace"
fi
git -C "$ORACLE/fireplace" fetch --quiet origin "$FIREPLACE_COMMIT" || true
git -C "$ORACLE/fireplace" checkout --quiet "$FIREPLACE_COMMIT"
git -C "$ORACLE/fireplace" lfs pull

[ -d "$ORACLE/venv" ] || "$PY" -m venv "$ORACLE/venv"
# setuptools<81: Fireplace still imports pkg_resources.
"$ORACLE/venv/Scripts/python.exe" -m pip install --quiet "setuptools<81" -e "$ORACLE/fireplace"

cd "$(dirname "$0")/../.."
"$ORACLE/venv/Scripts/python.exe" -W ignore tools/oracle/card_drift.py
echo "oracle ready: $ORACLE/venv/Scripts/python.exe tools/oracle/oracle.py"
