#!/usr/bin/env bash
# Runs every dev-shell suite: zsh always, PowerShell when the Windows
# PowerShells are reachable (from WSL; otherwise that suite skips with a
# note). Each suite prints PASS/FAIL lines and a RESULT line; this exits
# non-zero when any suite fails.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
status=0
echo "=== engine unit tests (pure zsh) ==="; zsh "$here/engine.test.zsh" || status=1
echo; echo "=== zsh suite ==="; bash "$here/install-sh.test.sh" || status=1
echo; echo "=== PowerShell suite ==="; bash "$here/install-ps1.test.sh" || status=1
exit $status
