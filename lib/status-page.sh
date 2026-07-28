# templatehash playground — localhost landing page.
# An agnostic playground home: short intro, faucet link, and the list of projects.
# bark's live status is shown inline in its project card. Loaded by the flake into a
# writeShellScriptBin wrapper that puts bark/jq/curl/python3 on PATH.
set -euo pipefail

ARK="${TEMPLATEHASH_ARK:-ark.templatehash.com}"
ESPLORA="${TEMPLATEHASH_ESPLORA:-https://esplora.signet.2nd.dev}"
FAUCET="https://signet.2nd.dev"
LEARN="https://github.com/bip448"
REPO="https://github.com/mvuk/templatehash-playground"
PORT="${PLAYGROUND_PORT:-4848}"
DATADIR="${BARK_DATADIR:-$PWD/playground-data/bark-templatehash}"
export BARK_DATADIR="$DATADIR"
mkdir -p "$(dirname "$DATADIR")"

echo "== templatehash playground =="
if [ ! -e "$DATADIR/db.sqlite" ]; then
  echo "Creating the bark-templatehash wallet (for its live status card)…"
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
    ark_detail="live · ${pk:0:16}…"
  fi
  esp_ok=bad; esp_detail="unreachable"
  if height="$(curl -sf --max-time 8 "$ESPLORA/blocks/tip/height" 2>/dev/null)"; then
    esp_ok=ok; esp_detail="tip $height"
  fi
  fau_ok=bad
  curl -sf --max-time 8 -o /dev/null "$FAUCET" 2>/dev/null && fau_ok=ok
  wal_ok=bad; wal_detail="not created"
  [ -e "$DATADIR/db.sqlite" ] && { wal_ok=ok; wal_detail="ready"; }
  bal="$(bark -q balance 2>/dev/null | jq -r '.spendable_sat' 2>/dev/null || echo '?')"
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
  *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
  .wrap{max-width:720px;margin:0 auto;padding:32px 20px}
  h1{font-size:23px;margin:0 0 6px}
  .intro{color:var(--mut);margin:0 0 18px}
  h2{font-size:13px;text-transform:uppercase;letter-spacing:.06em;color:var(--mut);margin:22px 0 10px}
  a.btn{display:block;text-align:center;text-decoration:none;background:var(--accent);color:#fff;padding:13px;border-radius:11px;font-weight:600}
  a.btn.sec{background:transparent;color:var(--fg);border:1px solid var(--line);font-weight:500}
  .card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px 18px;margin-bottom:14px}
  .head{display:flex;align-items:center;gap:10px}
  .num{flex:0 0 auto;width:22px;height:22px;border-radius:50%;background:var(--accent);color:#fff;font-size:13px;font-weight:700;display:flex;align-items:center;justify-content:center}
  .name{font-weight:700;font-size:16px}.tag{color:var(--mut);font-size:12px;margin-left:auto}
  .pd{color:var(--mut);font-size:14px;margin:8px 0 10px}
  .run{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:13px;background:color-mix(in srgb,var(--accent) 10%,transparent);border:1px solid var(--line);border-radius:8px;padding:8px 10px;margin:0}
  .mini{margin-top:11px;padding-top:11px;border-top:1px solid var(--line);font-size:13px;color:var(--mut)}
  .mini b{color:var(--fg)}
  .dot{display:inline-block;width:9px;height:9px;border-radius:50%;vertical-align:middle;margin-right:2px}
  .dot.ok{background:var(--ok)}.dot.bad{background:var(--bad)}
  .mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px;word-break:break-all;color:var(--mut)}
  .foot{color:var(--mut);font-size:12px;margin-top:20px;text-align:center}
  a{color:var(--accent)}
</style></head><body><div class="wrap">
  <h1>templatehash playground</h1>
  <p class="intro">A hands-on playground for the <b>BIP448 bundle</b> — Taproot-native rebindable
     transactions (covenants + eltoo) — running live on Bitcoin <b>signet</b>. Pick a project below.</p>

  <a class="btn" href="$FAUCET" target="_blank" rel="noopener">💧 Get signet test coins → signet.2nd.dev</a>

  <h2>Projects</h2>

  <div class="card">
    <div class="head"><span class="num">1</span><span class="name">LN-Symmetry (eltoo)</span>
      <span class="tag">Core Lightning</span></div>
    <p class="pd">Rebindable Lightning channels (eltoo): a symmetric “latest-state-wins” ratchet with
       <b>no penalty transactions</b>, via <code>ANYPREVOUT</code> / <code>CSFS</code>+<code>TEMPLATEHASH</code>.</p>
    <p class="run">./playground ln-symmetry</p>
  </div>

  <div class="card">
    <div class="head"><span class="num">2</span><span class="name">templatehash Ark (bark)</span>
      <span class="tag">$(dot "$ark_ok")$ark_detail</span></div>
    <p class="pd">A covenant Ark wallet using <code>OP_TEMPLATEHASH</code>, pointed at the hosted
       <code>ark.templatehash.com</code> server. Runs the bark <b>client</b> — no captaind of your own.</p>
    <p class="run">./playground bark-templatehash</p>
    <div class="mini">
      $(dot "$wal_ok")wallet $wal_detail &nbsp;·&nbsp; $(dot "$esp_ok")chain $esp_detail &nbsp;·&nbsp; $(dot "$fau_ok")faucet
      &nbsp;·&nbsp; spendable <b>$bal sat</b><br>
      <span class="mono">VTXO: $VTXO</span><br>
      <span class="mono">on-chain: $ONCHAIN</span>
    </div>
  </div>

  <div class="btns"><a class="btn sec" href="$LEARN" target="_blank" rel="noopener">About the BIP448 bundle</a></div>
  <p class="foot">Public signet · deep-dive docs + source: <a href="$REPO" target="_blank" rel="noopener">the repo</a> · updated $now (auto-refresh 15s)</p>
</div></body></html>
HTML
}

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
