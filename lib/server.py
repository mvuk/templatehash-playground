#!/usr/bin/env python3
"""templatehash playground control server.

Serves the built shadcn UI (PLAYGROUND_UI) and exposes a tiny local control API:
  GET  /status.json         -> live status (bark client wallet + eltoo node running?)
  POST /api/eltoo/toggle     -> start / stop the local eltoo lightningd
  POST /api/test/eltoo       -> run the eltoo settle-tx unit test
  POST /api/test/bark        -> run feature_templatehash.py against bitcoind-inquisition

Binary/path config comes from env (injected by the flake's status app). Everything runs
against the public Bitcoin Inquisition signet. This is a LOCAL control plane — it starts
and stops processes on this machine.
"""
import http.server
import json
import os
import socket
import subprocess
import time
import urllib.request
from pathlib import Path

UI = os.environ["PLAYGROUND_UI"]
PORT = int(os.environ.get("PLAYGROUND_PORT", "4848"))
HOST = os.environ.get("PLAYGROUND_HOST", "127.0.0.1")
ARK = os.environ.get("TEMPLATEHASH_ARK", "ark.templatehash.com")
ESPLORA = os.environ.get("TEMPLATEHASH_ESPLORA", "https://esplora.signet.2nd.dev")
FAUCET = "https://signet.2nd.dev"
BARK_DATADIR = os.environ["BARK_DATADIR"]
NODE_DATADIR = os.environ.get("INQUISITION_DATADIR", os.path.join(os.getcwd(), "playground-data/inquisition"))
LN_DIR = os.environ.get("LN_DIR", os.path.join(os.getcwd(), "playground-data/ln"))
RUN_SETTLE_TX = os.environ.get("RUN_SETTLE_TX", "")   # eltoo unit-test binary
INQ_SRC = os.environ.get("INQ_SRC", "")               # inquisition source (functional tests)
INQ_PKG = os.environ.get("INQ_PKG", "")               # bitcoind-inquisition package (bin/bitcoind)
RUNDIR = Path(os.environ.get("PLAYGROUND_RUN", os.path.join(os.getcwd(), "playground-data/run")))
RUNDIR.mkdir(parents=True, exist_ok=True)

ENV = {**os.environ, "BARK_DATADIR": BARK_DATADIR}
ADDR_CACHE = {}


def sh(cmd, timeout=30, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=ENV, **kw)


def bark(*args, timeout=45):
    return sh(["bark", "-q", *args], timeout=timeout)


def http_ok(url, timeout=8):
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return r.status, r.read().decode(errors="replace").strip()
    except Exception:
        return None, None


def pidfile(name):
    return RUNDIR / f"{name}.pid"


def running(name):
    pf = pidfile(name)
    if not pf.exists():
        return False
    try:
        pid = int(pf.read_text().strip())
        os.kill(pid, 0)
        return True
    except Exception:
        pf.unlink(missing_ok=True)
        return False


def spawn(name, cmd):
    log = open(RUNDIR / f"{name}.log", "ab")
    p = subprocess.Popen(cmd, stdout=log, stderr=log, env=ENV, start_new_session=True)
    pidfile(name).write_text(str(p.pid))
    return p.pid


def stop(name):
    pf = pidfile(name)
    if pf.exists():
        try:
            os.kill(int(pf.read_text().strip()), 15)
        except Exception:
            pass
        pf.unlink(missing_ok=True)


def node_rpc_up():
    s = socket.socket()
    s.settimeout(1)
    try:
        s.connect(("127.0.0.1", 38332))
        return True
    except Exception:
        return False
    finally:
        s.close()


def status():
    ark_ok = bark("ark-info").returncode == 0
    wal_ok = os.path.exists(os.path.join(BARK_DATADIR, "db.sqlite"))
    esp_code, esp_height = http_ok(f"{ESPLORA}/blocks/tip/height")
    fau_code, _ = http_ok(FAUCET)
    try:
        bal = json.loads(bark("balance").stdout).get("spendable_sat", "?")
    except Exception:
        bal = "?"
    # cache addresses only once we actually get them (don't freeze a transient failure)
    if ADDR_CACHE.get("vtxo", "n/a") == "n/a":
        v = (bark("address").stdout or "").strip()
        if v.startswith("tark"):
            ADDR_CACHE["vtxo"] = v
    if ADDR_CACHE.get("onchain", "n/a") == "n/a":
        try:
            a = json.loads(bark("onchain", "address").stdout).get("address", "")
            if a:
                ADDR_CACHE["onchain"] = a
        except Exception:
            pass
    return {
        "ark": {"ok": ark_ok, "detail": "reachable" if ark_ok else "unreachable"},
        "wallet": {"ok": wal_ok, "detail": "ready" if wal_ok else "not created"},
        "esplora": {"ok": esp_code == 200, "detail": f"tip {esp_height}" if esp_height else "unreachable"},
        "faucet": {"ok": fau_code == 200},
        "spendable_sat": bal,
        "vtxo": ADDR_CACHE.get("vtxo", "n/a"),
        "onchain": ADDR_CACHE.get("onchain", "n/a"),
        "ln_running": running("lightningd"),
        "node_running": running("bitcoind") or node_rpc_up(),
        "updated": time.strftime("%H:%M:%S"),
    }


def toggle_eltoo():
    if running("lightningd"):
        stop("lightningd")
        return {"ok": True, "running": False, "msg": "eltoo lightningd stopped"}
    Path(LN_DIR).mkdir(parents=True, exist_ok=True)
    started = []
    if not (running("bitcoind") or node_rpc_up()):
        Path(NODE_DATADIR).mkdir(parents=True, exist_ok=True)
        spawn("bitcoind", ["bitcoind", "-signet", f"-datadir={NODE_DATADIR}", "-txindex",
                           "-addnode=inquisition.bitcoin-signet.net"])
        started.append("bitcoind")
        for _ in range(30):
            if node_rpc_up():
                break
            time.sleep(1)
    spawn("lightningd", ["lightningd", "--network=signet", f"--lightning-dir={LN_DIR}",
                         f"--bitcoin-datadir={NODE_DATADIR}", "--bitcoin-rpcconnect=127.0.0.1",
                         "--bitcoin-rpcport=38332", "--developer", "--alias=eltoo-playground"])
    started.append("lightningd")
    msg = "started: " + ", ".join(started)
    if "bitcoind" in started:
        msg += " (node may need to finish signet sync before the channel demo works)"
    return {"ok": True, "running": True, "msg": msg}


def run_test(cmd, timeout, name):
    try:
        r = sh(cmd, timeout=timeout)
        out = (r.stdout + r.stderr)
        return {"ok": r.returncode == 0, "name": name, "log": out[-4000:]}
    except subprocess.TimeoutExpired:
        return {"ok": False, "name": name, "log": f"{name} timed out after {timeout}s"}
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "name": name, "log": f"{name} error: {e}"}


def test_eltoo():
    if not RUN_SETTLE_TX or not os.path.exists(RUN_SETTLE_TX):
        return {"ok": False, "name": "eltoo settle_tx", "log": "run-settle_tx binary not available"}
    return run_test([RUN_SETTLE_TX], 120, "eltoo settle_tx unit test")


# The foundation (item 0): the Bitcoin Inquisition consensus tests for the BIP448 bundle.
BUNDLE_TESTS = [
    ("feature_checktemplateverify.py", "OP_CHECKTEMPLATEVERIFY (CTV, BIP119)"),
    ("feature_templatehash.py", "OP_TEMPLATEHASH (BIP446)"),
    ("feature_taproot.py", "OP_CHECKSIGFROMSTACK (BIP348) + OP_INTERNALKEY (BIP349) + TEMPLATEHASH"),
]


def test_bundle():
    if not INQ_SRC or not INQ_PKG:
        return {"ok": False, "name": "BIP448 bundle", "log": "inquisition source/pkg not configured"}
    cfg = RUNDIR / "test-config.ini"
    cfg.write_text(
        "[environment]\n"
        f"SRCDIR={INQ_SRC}\nBUILDDIR={INQ_PKG}\nEXEEXT=\n"
        "[components]\nENABLE_WALLET=true\nENABLE_CLI=true\nENABLE_BITCOIND=true\n"
    )
    logs, all_ok = [], True
    for f, label in BUNDLE_TESTS:
        tmp = RUNDIR / ("bt-" + f)
        subprocess.run(["rm", "-rf", str(tmp)])
        r = run_test(["python3", f"{INQ_SRC}/test/functional/{f}",
                      f"--configfile={cfg}", f"--tmpdir={tmp}", f"--cachedir={RUNDIR}/cache"], 600, f)
        all_ok = all_ok and r["ok"]
        logs.append(f"### {f} — {label}: {'PASS' if r['ok'] else 'FAIL'}\n{(r['log'] or '')[-1200:]}")
    return {"ok": all_ok, "name": "BIP448 bundle consensus tests", "log": "\n\n".join(logs)}


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=UI, **k)

    def _json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.split("?")[0] == "/status.json":
            try:
                self._json(status())
            except Exception as e:  # noqa: BLE001
                self._json({"error": str(e)}, 500)
            return
        super().do_GET()

    def do_POST(self):
        routes = {
            "/api/eltoo/toggle": toggle_eltoo,
            "/api/test/eltoo": test_eltoo,
            "/api/test/bundle": test_bundle,
        }
        fn = routes.get(self.path.split("?")[0])
        if not fn:
            self._json({"error": "not found"}, 404)
            return
        try:
            self._json(fn())
        except Exception as e:  # noqa: BLE001
            self._json({"ok": False, "log": str(e)}, 500)

    def log_message(self, *a):
        pass


def main():
    print(f"== templatehash playground ==\n▶ Playground: http://localhost:{PORT}  (Ctrl-C to stop)")
    url = f"http://localhost:{PORT}"
    if os.environ.get("DISPLAY"):
        subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with http.server.ThreadingHTTPServer((HOST, PORT), Handler) as httpd:
        httpd.serve_forever()


if __name__ == "__main__":
    main()
