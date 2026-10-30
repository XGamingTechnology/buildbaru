#!/usr/bin/env bash
# Start the staging FXServer prepared by setup.sh (foreground; use inside tmux).
set -euo pipefail

BASE="${FX_STAGING_DIR:-$HOME/fxstaging}"

if grep -q 'sv_licenseKey "CHANGE_ME"' "$BASE/data/secrets.cfg"; then
  echo "Set your license key in $BASE/data/secrets.cfg first." >&2
  exit 1
fi

cd "$BASE/data"
exec "$BASE/server/run.sh" +exec server.cfg
