# templatehash playground — localhost status page.
# Ensures the default wallet exists, then serves a live status page that reflects
# REAL checks (wallet, Ark server, chain source, faucet, balance). Loaded by the flake into
# a writeShellScriptBin wrapper that puts bark/jq/curl/python3 on PATH.
set -euo pipefail

ARK="${TEMPLATEHASH_ARK:-ark.templatehash.com}"
ESPLORA="${TEMPLATEHASH_ESPLORA:-https://esplora.signet.2nd.dev}"
FAUCET="https://signet.2nd.dev"
LEARN="https://templatehash.com"
REPO="https://github.com/mvuk/templatehash-playground"
PORT="${PLAYGROUND_PORT:-4848}"
DATADIR="${BARK_DATADIR:-$PWD/playground-data/bark-templatehash}"
export BARK_DATADIR="$DATADIR"
mkdir -p "$(dirname "$DATADIR")"

echo "== templatehash playground =="
if [ ! -e "$DATADIR/db.sqlite" ]; then
  echo "Creating covenant-enabled signet wallet (Ark server: $ARK)…"
  bark create --signet --datadir "$DATADIR" --ark "$ARK" || true
else
  echo "Using wallet at $DATADIR"
fi
chmod 600 "$DATADIR/db.sqlite" 2>/dev/null || true

WEBROOT="$(mktemp -d)"
SERVER_PID=""; LOOP_PID=""
cleanup() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
  [ -n "$LOOP_PID" ] && kill "$LOOP_PID" 2>/dev/null || true
  rm -rf "$WEBROOT"
}
trap cleanup EXIT INT TERM

# Static, one-time reads (addresses don't change).
VTXO="$(bark -q address 2>/dev/null || echo 'n/a')"
ONCHAIN="$(bark -q onchain address 2>/dev/null | jq -r '.address' 2>/dev/null || echo 'n/a')"

dot() { if [ "$1" = ok ]; then printf '<span class="dot ok"></span>'; else printf '<span class="dot bad"></span>'; fi; }

generate() {
  ark_ok=bad; ark_detail="unreachable"
  if info="$(bark -q ark-info 2>/dev/null)"; then
    ark_ok=ok
    pk="$(printf '%s' "$info" | jq -r '.server_pubkey' 2>/dev/null || echo '')"
    ark_detail="server pubkey ${pk:0:20}…"
  fi
  esp_ok=bad; esp_detail="unreachable"
  if height="$(curl -sf --max-time 8 "$ESPLORA/blocks/tip/height" 2>/dev/null)"; then
    esp_ok=ok; esp_detail="signet tip height $height"
  fi
  fau_ok=bad
  curl -sf --max-time 8 -o /dev/null "$FAUCET" 2>/dev/null && fau_ok=ok
  wal_ok=bad; wal_detail="not created"
  [ -e "$DATADIR/db.sqlite" ] && { wal_ok=ok; wal_detail="ready"; }
  bal="$(bark -q balance 2>/dev/null | jq -r '.spendable_sat' 2>/dev/null || echo '?')"

  all_ok="Connected to signet · Ark server live"
  [ "$ark_ok" = ok ] && [ "$esp_ok" = ok ] || all_ok="Some services unreachable — check your network"
  now="$(date '+%H:%M:%S')"

  cat > "$WEBROOT/index.html" <<HTML
<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="15">
<title>templatehash playground</title>
<style>
  :root{--bg:#f7f8fa;--card:#fff;--fg:#141719;--mut:#5c6470;--line:#e6e8ec;--ok:#1a9d5a;--bad:#d1453b;--accent:#6b4cf6}
  @media(prefers-color-scheme:dark){:root{--bg:#0e1013;--card:#171a1f;--fg:#eef1f4;--mut:#9aa3af;--line:#262a31;--ok:#2ec77a;--bad:#f2645a;--accent:#9b83ff}}
  *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
  .wrap{max-width:720px;margin:0 auto;padding:32px 20px}
  h1{font-size:22px;margin:0 0 2px}.sub{color:var(--mut);margin:0 0 20px;font-size:13px}
  .banner{background:linear-gradient(90deg,color-mix(in srgb,var(--ok) 16%,transparent),transparent);border:1px solid var(--line);border-radius:12px;padding:14px 16px;margin-bottom:18px;font-weight:600}
  .card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:8px 16px;margin-bottom:16px}
  .row{display:flex;align-items:center;gap:12px;padding:12px 0;border-bottom:1px solid var(--line)}.row:last-child{border-bottom:0}
  .dot{width:11px;height:11px;border-radius:50%;flex:0 0 auto;box-shadow:0 0 0 3px color-mix(in srgb,currentColor 22%,transparent)}
  .dot.ok{background:var(--ok);color:var(--ok)}.dot.bad{background:var(--bad);color:var(--bad)}
  .k{font-weight:600}.d{color:var(--mut);font-size:13px;margin-left:auto;text-align:right}
  .mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;word-break:break-all;color:var(--mut)}
  .bal{font-size:28px;font-weight:700}
  .btns{display:flex;gap:10px;flex-wrap:wrap;margin-top:6px}
  a.btn{flex:1;min-width:150px;text-align:center;text-decoration:none;background:var(--accent);color:#fff;padding:12px;border-radius:10px;font-weight:600}
  a.btn.sec{background:transparent;color:var(--fg);border:1px solid var(--line)}
  .foot{color:var(--mut);font-size:12px;margin-top:18px;text-align:center}
</style></head><body><div class="wrap">
  <h1>templatehash playground</h1>
  <p class="sub">BIP448 bundle playground · project 1: <b>bark-templatehash</b> — a bark <b>client</b> (OP_TEMPLATEHASH) on public signet</p>
  <div class="banner">$(dot "$ark_ok") &nbsp;$all_ok</div>
  <div class="card">
    <div class="row">$(dot "$wal_ok")<span class="k">bark wallet</span><span class="d">$wal_detail</span></div>
    <div class="row">$(dot "$ark_ok")<span class="k">Ark server</span><span class="d">$ARK · $ark_detail</span></div>
    <div class="row">$(dot "$esp_ok")<span class="k">Chain source (esplora)</span><span class="d">$esp_detail</span></div>
    <div class="row">$(dot "$fau_ok")<span class="k">Faucet</span><span class="d">signet.2nd.dev</span></div>
  </div>
  <div class="card">
    <div class="row"><span class="k">Spendable</span><span class="d"><span class="bal">$bal</span> sat</span></div>
    <div class="row"><span class="k">VTXO address</span></div><div class="mono">$VTXO</div>
    <div class="row"><span class="k">On-chain address</span></div><div class="mono">$ONCHAIN</div>
  </div>
  <div class="btns">
    <a class="btn" href="$FAUCET" target="_blank" rel="noopener">Get test sats →</a>
    <a class="btn sec" href="$LEARN" target="_blank" rel="noopener">What is OP_TEMPLATEHASH?</a>
    <a class="btn sec" href="$REPO" target="_blank" rel="noopener">Add a demo (PR)</a>
  </div>
  <p class="foot">Phase 1: connected to the public signet via the hosted Ark server — no local node runs yet.<br>Updated $now · auto-refresh 15s</p>
</div></body></html>
HTML
}

generate
( while true; do sleep 15; generate 2>/dev/null || true; done ) &
LOOP_PID=$!

# Pick a free port if the requested one is taken.
PORT="$(python3 - "$PORT" <<'PY'
import socket, sys
start = int(sys.argv[1])
for c in range(start, start + 20):
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)  # match http.server so TIME_WAIT ports are reusable
    try:
        s.bind(("127.0.0.1", c)); s.close(); print(c); break
    except OSError:
        s.close()
else:
    print(start)
PY
)"

URL="http://localhost:$PORT"
echo ""
echo "▶ Status page: $URL   (Ctrl-C to stop)"
if [ -n "${DISPLAY:-}" ] && command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$URL" >/dev/null 2>&1 || true
elif [ "$(uname)" = "Darwin" ] && command -v open >/dev/null 2>&1; then
  open "$URL" >/dev/null 2>&1 || true
fi

python3 -m http.server "$PORT" --directory "$WEBROOT" >/dev/null 2>&1 &
SERVER_PID=$!
wait "$SERVER_PID"
