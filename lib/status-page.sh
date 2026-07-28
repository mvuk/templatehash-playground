# templatehash playground — serves the shadcn UI + a live status.json.
# The React app (built into $PLAYGROUND_UI) fetches ./status.json every 15s.
# Loaded by the flake into a writeShellScriptBin wrapper that puts
# bark/jq/curl/python3/pgrep on PATH and exports PLAYGROUND_UI.
set -euo pipefail

ARK="${TEMPLATEHASH_ARK:-ark.templatehash.com}"
ESPLORA="${TEMPLATEHASH_ESPLORA:-https://esplora.signet.2nd.dev}"
FAUCET="https://signet.2nd.dev"
PORT="${PLAYGROUND_PORT:-4848}"
DATADIR="${BARK_DATADIR:-$PWD/playground-data/bark-templatehash}"
UI="${PLAYGROUND_UI:?PLAYGROUND_UI (path to the built shadcn dist) must be set}"
export BARK_DATADIR="$DATADIR"
mkdir -p "$(dirname "$DATADIR")"

echo "== templatehash playground =="
if [ ! -e "$DATADIR/db.sqlite" ]; then
  echo "Creating the bark-templatehash client wallet (for its live status)…"
  bark create --signet --datadir "$DATADIR" --ark "$ARK" || true
else
  echo "Using bark client wallet at $DATADIR"
fi
chmod 600 "$DATADIR/db.sqlite" 2>/dev/null || true

WEBROOT="$(mktemp -d)"
cp -r "$UI"/. "$WEBROOT"/
chmod -R u+w "$WEBROOT"
SERVER_PID=""; LOOP_PID=""
cleanup() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
  [ -n "$LOOP_PID" ] && kill "$LOOP_PID" 2>/dev/null || true
  rm -rf "$WEBROOT"
}
trap cleanup EXIT INT TERM

# Static, one-time reads (addresses don't change for a given wallet).
VTXO="$(bark -q address 2>/dev/null || echo 'n/a')"
ONCHAIN="$(bark -q onchain address 2>/dev/null | jq -r '.address' 2>/dev/null || echo 'n/a')"

generate() {
  local ark_ok=false ark_detail="unreachable"
  if bark -q ark-info >/dev/null 2>&1; then ark_ok=true; ark_detail="reachable"; fi
  local esp_ok=false esp_detail="unreachable"
  if height="$(curl -sf --max-time 8 "$ESPLORA/blocks/tip/height" 2>/dev/null)"; then
    esp_ok=true; esp_detail="tip $height"
  fi
  local fau_ok=false
  curl -sf --max-time 8 -o /dev/null "$FAUCET" 2>/dev/null && fau_ok=true
  local wal_ok=false wal_detail="not created"
  [ -e "$DATADIR/db.sqlite" ] && { wal_ok=true; wal_detail="ready"; }
  local bal
  bal="$(bark -q balance 2>/dev/null | jq -r '.spendable_sat' 2>/dev/null || echo '?')"
  # (project #1) is the eltoo lightningd process running locally on this machine?
  local ln_running=false
  pgrep -f "/bin/lightningd" >/dev/null 2>&1 && ln_running=true

  jq -n \
    --argjson ark_ok "$ark_ok" --arg ark_detail "$ark_detail" \
    --argjson wal_ok "$wal_ok" --arg wal_detail "$wal_detail" \
    --argjson esp_ok "$esp_ok" --arg esp_detail "$esp_detail" \
    --argjson fau_ok "$fau_ok" \
    --arg spendable "$bal" --arg vtxo "$VTXO" --arg onchain "$ONCHAIN" \
    --argjson ln_running "$ln_running" --arg updated "$(date '+%H:%M:%S')" \
    '{ark:{ok:$ark_ok,detail:$ark_detail}, wallet:{ok:$wal_ok,detail:$wal_detail},
      esplora:{ok:$esp_ok,detail:$esp_detail}, faucet:{ok:$fau_ok},
      spendable_sat: ($spendable|tonumber? // $spendable),
      vtxo:$vtxo, onchain:$onchain, ln_running:$ln_running, updated:$updated}' \
    > "$WEBROOT/status.json"
}

# Pick a free port if the requested one is taken.
PORT="$(python3 - "$PORT" <<'PY'
import socket, sys
start = int(sys.argv[1])
for c in range(start, start + 20):
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind(("127.0.0.1", c)); s.close(); print(c); break
    except OSError:
        s.close()
else:
    print(start)
PY
)"

generate
( while true; do sleep 15; generate 2>/dev/null || true; done ) &
LOOP_PID=$!

URL="http://localhost:$PORT"
echo ""
echo "▶ Playground: $URL   (Ctrl-C to stop)"
if [ -n "${DISPLAY:-}" ] && command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$URL" >/dev/null 2>&1 || true
elif [ "$(uname)" = "Darwin" ] && command -v open >/dev/null 2>&1; then
  open "$URL" >/dev/null 2>&1 || true
fi

python3 -m http.server "$PORT" --directory "$WEBROOT" >/dev/null 2>&1 &
SERVER_PID=$!
wait "$SERVER_PID"
