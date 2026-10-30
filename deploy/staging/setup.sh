#!/usr/bin/env bash
# Staging FXServer for Sentinel RP on Ubuntu 22.04/24.04. NOT for production.
# Safe to re-run: existing artifact, secrets and applied migrations are kept.
#
# Required:
#   FX_ARTIFACT_URL   Linux fx.tar.xz from https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/
#   OXMYSQL_VERSION   oxmysql release tag to install (license review pending, D-09)
#   OX_LIB_VERSION    ox_lib release tag (the release zip contains the built UI)
#   QBX_CORE_VERSION  qbx_core git tag (ADR 0003; GPL-3.0)
# Optional:
#   FX_STAGING_DIR (default ~/fxstaging), REPO_URL, REPO_REF (default main)
#
# qbx_core needs FXServer artifact 10731 or newer and OneSync.
#
# The license key is never passed here: edit secrets.cfg on the host afterwards.
set -euo pipefail

: "${FX_ARTIFACT_URL:?set FX_ARTIFACT_URL to a Linux fx.tar.xz URL from the FiveM artifacts page}"
: "${OXMYSQL_VERSION:?set OXMYSQL_VERSION to a reviewed oxmysql release tag}"
: "${OX_LIB_VERSION:?set OX_LIB_VERSION to a reviewed ox_lib release tag}"
: "${QBX_CORE_VERSION:?set QBX_CORE_VERSION to a reviewed qbx_core git tag}"
REPO_URL="${REPO_URL:-https://github.com/XGamingTechnology/buildbaru.git}"
REPO_REF="${REPO_REF:-main}"
BASE="${FX_STAGING_DIR:-$HOME/fxstaging}"
DB_NAME="sentinel_staging"
DB_USER="sentinel_app"

log() { printf '\n==> %s\n' "$*"; }

log "Installing packages"
sudo apt-get update -q
sudo apt-get install -y -q mariadb-server git curl xz-utils unzip tmux openssl

mkdir -p "$BASE/server" "$BASE/data/resources"

log "FXServer artifact"
if [ ! -x "$BASE/server/run.sh" ]; then
  curl -fL "$FX_ARTIFACT_URL" -o "$BASE/fx.tar.xz"
  sha256sum "$BASE/fx.tar.xz"
  tar -xJf "$BASE/fx.tar.xz" -C "$BASE/server"
  rm "$BASE/fx.tar.xz"
else
  echo "already installed in $BASE/server (delete it to change versions)"
fi

log "Repository ($REPO_REF)"
if [ -d "$BASE/buildbaru/.git" ]; then
  git -C "$BASE/buildbaru" fetch -q origin "$REPO_REF"
  git -C "$BASE/buildbaru" checkout -q FETCH_HEAD
else
  git clone -q "$REPO_URL" "$BASE/buildbaru"
  git -C "$BASE/buildbaru" checkout -q "$REPO_REF"
fi
git -C "$BASE/buildbaru" log --oneline -1

log "Linking resources"
for group in '[sentinel]' '[rp]' '[dev]'; do
  ln -sfn "$BASE/buildbaru/fivem/resources/$group" "$BASE/data/resources/$group"
done

# Installs <name> from <owner>/<name> release asset <name>.zip at <tag>.
install_release_zip() {
  local owner="$1" name="$2" tag="$3" tmp manifest
  log "$name $tag"
  if [ -f "$BASE/data/resources/$name/fxmanifest.lua" ]; then
    echo "already installed (delete $BASE/data/resources/$name to change versions)"
    return
  fi
  tmp="$(mktemp -d)"
  curl -fL "https://github.com/$owner/$name/releases/download/$tag/$name.zip" -o "$tmp/$name.zip"
  sha256sum "$tmp/$name.zip"
  unzip -q "$tmp/$name.zip" -d "$tmp/unzipped"
  manifest="$(find "$tmp/unzipped" -name fxmanifest.lua -path "*$name*" | head -n 1)"
  [ -n "$manifest" ] || { echo "$name.zip has no fxmanifest.lua; check the release asset" >&2; exit 1; }
  cp -r "$(dirname "$manifest")" "$BASE/data/resources/$name"
  rm -rf "$tmp"
}
install_release_zip overextended oxmysql "$OXMYSQL_VERSION"
install_release_zip overextended ox_lib "$OX_LIB_VERSION"

log "qbx_core $QBX_CORE_VERSION"
QBX="$BASE/data/resources/qbx_core"
if [ ! -f "$QBX/fxmanifest.lua" ]; then
  git -c advice.detachedHead=false clone -q --depth 1 --branch "$QBX_CORE_VERSION" \
    https://github.com/Qbox-Project/qbx_core.git "$QBX"
  git -C "$QBX" log --oneline -1
  # Route paychecks through the ledger (docs/QBOX.md). Patched only if the
  # stock function is found unchanged; otherwise edit it by hand.
  python3 -I - "$QBX/config/server.lua" <<'PY' || echo "WARNING: patch config/server.lua sendPaycheck by hand (docs/QBOX.md)"
import sys
path = sys.argv[1]
src = open(path, encoding='utf-8').read()
old = """    sendPaycheck = function (player, payment)
        player.Functions.AddMoney('bank', payment)
        Notify(player.PlayerData.source, locale('info.received_paycheck', payment))
        TriggerEvent('qbx_core:server:onPaycheck', player.PlayerData.source, payment)
    end,"""
new = """    sendPaycheck = function (player, payment)
        -- Sentinel RP: paychecks go through the econ ledger (ADR 0003).
        local result = exports.rp_qbx_bridge:Paycheck(player.PlayerData.source, payment)
        if result.ok then
            Notify(player.PlayerData.source, locale('info.received_paycheck', payment))
            TriggerEvent('qbx_core:server:onPaycheck', player.PlayerData.source, payment)
        end
    end,"""
if src.count(old) != 1:
    sys.exit(1)
open(path, 'w', encoding='utf-8').write(src.replace(old, new))
print("patched sendPaycheck to use rp_qbx_bridge:Paycheck")
PY
else
  echo "already installed (delete $QBX to change versions)"
fi

log "Database $DB_NAME (local only)"
sudo mariadb -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
SECRETS="$BASE/data/secrets.cfg"
if [ ! -f "$SECRETS" ]; then
  db_pass="$(openssl rand -hex 24)"
  sudo mariadb -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$db_pass';
                   ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$db_pass';"
  (
    umask 077
    cat > "$SECRETS" <<EOF
# Generated by deploy/staging/setup.sh. Never commit or paste this file.
sv_licenseKey "CHANGE_ME"
set mysql_connection_string "mysql://$DB_USER:$db_pass@localhost/$DB_NAME?charset=utf8mb4"
set sentinel_ingest_token ""
EOF
  )
  echo "created $SECRETS (mode 600)"
else
  echo "keeping existing $SECRETS"
fi
# Least privilege: the game may only read and call procedures, never UPDATE balances.
sudo mariadb -e "GRANT SELECT, EXECUTE ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost'"

log "Migrations"
MIG="$BASE/buildbaru/db/migrations"
sudo mariadb "$DB_NAME" < "$MIG/0000_schema_migrations.up.sql"
apply() {
  local version="$1" file="$2" applied
  applied="$(sudo mariadb -N "$DB_NAME" -e "SELECT COUNT(*) FROM schema_migrations WHERE version = $version")"
  if [ "$applied" = "0" ]; then
    sudo mariadb "$DB_NAME" < "$MIG/$file"
    echo "applied $file"
  else
    echo "already applied $file"
  fi
}
apply 1 0001_economy_ledger.up.sql
apply 2 0002_operator_workflow.up.sql
apply 3 0003_econ_open_account.up.sql
sudo mariadb "$DB_NAME" < "$QBX/qbx_core.sql"
echo "applied qbx_core.sql"
# Qbox tables need normal DML; ledger and ops tables stay SELECT/EXECUTE only.
for table in $(sudo mariadb -N "$DB_NAME" -e "SELECT table_name FROM information_schema.tables
    WHERE table_schema = '$DB_NAME' AND table_type = 'BASE TABLE'
      AND table_name NOT LIKE 'econ\\_%' AND table_name NOT LIKE 'ops\\_%'
      AND table_name <> 'schema_migrations'"); do
  sudo mariadb -e "GRANT SELECT, INSERT, UPDATE, DELETE ON \`$DB_NAME\`.\`$table\` TO '$DB_USER'@'localhost'"
  echo "granted DML on $table"
done
sudo mariadb "$DB_NAME" < "$BASE/buildbaru/deploy/staging/seed_selftest.sql" >/dev/null
echo "selftest accounts seeded"

log "server.cfg"
CFG="$BASE/data/server.cfg"
if [ ! -f "$CFG" ]; then
  sed -e 's|^# endpoint_add_tcp "<bind-address>:30120"|endpoint_add_tcp "0.0.0.0:30120"|' \
      -e 's|^# endpoint_add_udp "<bind-address>:30120"|endpoint_add_udp "0.0.0.0:30120"|' \
      -e 's|^sv_hostname .*|sv_hostname "Sentinel RP (staging)"|' \
      "$BASE/buildbaru/fivem/server.cfg.example" > "$CFG"
  cat >> "$CFG" <<'EOF'

# --- Staging only ---
sv_master1 ""               # do not list on the public server browser
set sentinel_selftest 1
ensure sentinel_selftest
EOF
  echo "created $CFG"
else
  echo "keeping existing $CFG"
fi

cat <<EOF

Done. Next:
  1. Put your keymaster license key in $SECRETS (replace CHANGE_ME).
  2. Allow only your own IP to port 30120 (TCP+UDP) in the VPS firewall / security group.
  3. Start:  $BASE/buildbaru/deploy/staging/run.sh
     and look for "[selftest] SUMMARY" in the console.
EOF
