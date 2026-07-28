#!/usr/bin/env python3
"""templatehash playground control server.

Serves the built shadcn UI (PLAYGROUND_UI) and exposes a tiny local control API:
  GET  /status.json           -> live status (only for components that are ENABLED)
  POST /api/toggle/<name>     -> enable / disable a component: node | wallet | eltoo | explorer
  POST /api/eltoo/toggle      -> legacy alias for /api/toggle/eltoo
  POST /api/test/eltoo        -> run the eltoo settle-tx unit test
  POST /api/test/bundle       -> run the BIP448 consensus tests against bitcoind-inquisition

ARRIVAL STATE — deliberately minimal. On first run the only thing alive is component 0,
the Bitcoin Inquisition signet node, plus this web process on :4848. Nothing else is
started and nothing is pre-provisioned: no Ark wallet is created, no lightningd, no
explorer. Each is opt-in via its toggle.

That minimalism is enforced in status(): a component that is disabled is NOT probed, so
the "off" state makes no subprocess calls and no outbound network requests to the Ark
server, esplora or the faucet. Only enabled components cost anything.

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

EXPLORER_PORT = int(os.environ.get("EXPLORER_PORT", "3002"))
ENV = {**os.environ, "BARK_DATADIR": BARK_DATADIR}
ADDR_CACHE = {}

# ---- component enablement ---------------------------------------------------
# Process-backed components (eltoo, explorer, node) derive "enabled" from a live pid.
# `wallet` has no process, so its flag is persisted here. Disabling the wallet never
# deletes it — the wallet may hold signet funds — it only stops probing and hides it.
STATE_FILE = RUNDIR / "components.json"
COMPONENTS = ("node", "wallet", "eltoo", "explorer")


def load_state():
    try:
        return json.loads(STATE_FILE.read_text())
    except Exception:
        return {}


def save_state(st):
    STATE_FILE.write_text(json.dumps(st))


def enabled(name):
    """Is this component currently on? Live process beats stored flag."""
    if name == "node":
        return running("bitcoind") or node_rpc_up()
    if name == "eltoo":
        return running("lightningd")
    if name == "explorer":
        return running("explorer")
    if name == "wallet":
        # on only if explicitly enabled AND actually provisioned
        return bool(load_state().get("wallet")) and os.path.exists(
            os.path.join(BARK_DATADIR, "db.sqlite"))
    return False


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


def node_info():
    """Sync state of component 0, read straight from the node's own RPC."""
    if not INQ_PKG:
        return {}
    try:
        r = sh([f"{INQ_PKG}/bin/bitcoin-cli", "-signet", f"-datadir={NODE_DATADIR}",
                "getblockchaininfo"], timeout=10)
        if r.returncode != 0:
            return {}
        d = json.loads(r.stdout)
        return {
            "blocks": d.get("blocks"),
            "headers": d.get("headers"),
            "progress": round(d.get("verificationprogress", 0) * 100, 2),
            "ibd": d.get("initialblockdownload"),
        }
    except Exception:
        return {}


def status():
    """Report only what is enabled.

    A disabled component costs nothing: no subprocess, no outbound request. This is what
    keeps the arrival state minimal — with everything off, the only work done here is
    checking a few pidfiles.
    """
    en = {c: enabled(c) for c in COMPONENTS}
    out = {
        "enabled": en,
        "components": list(COMPONENTS),
        # legacy keys the current UI still reads
        "ln_running": en["eltoo"],
        "node_running": en["node"],
        "updated": time.strftime("%H:%M:%S"),
    }

    if en["node"]:
        out["node"] = node_info()

    if en["explorer"]:
        out["explorer"] = {"ok": True, "url": f"http://localhost:{EXPLORER_PORT}"}

    # Everything below talks to bark and the outside world — only when the wallet is on.
    if en["wallet"]:
        ark_ok = bark("ark-info").returncode == 0
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
        out.update({
            "ark": {"ok": ark_ok, "detail": "reachable" if ark_ok else "unreachable"},
            "wallet": {"ok": True, "detail": "ready"},
            "esplora": {"ok": esp_code == 200,
                        "detail": f"tip {esp_height}" if esp_height else "unreachable"},
            "faucet": {"ok": fau_code == 200},
            "spendable_sat": bal,
            "vtxo": ADDR_CACHE.get("vtxo", "n/a"),
            "onchain": ADDR_CACHE.get("onchain", "n/a"),
        })
    else:
        out["wallet"] = {"ok": False, "detail": "disabled"}

    return out


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


def start_node():
    """Bring up component 0. Idempotent."""
    if running("bitcoind") or node_rpc_up():
        return False
    Path(NODE_DATADIR).mkdir(parents=True, exist_ok=True)
    spawn("bitcoind", ["bitcoind", "-signet", f"-datadir={NODE_DATADIR}", "-txindex", "-server"])
    return True


def toggle_node():
    if enabled("node"):
        stop("bitcoind")
        return {"ok": True, "running": False, "msg": "inquisition node stopped"}
    start_node()
    return {"ok": True, "running": True, "msg": "inquisition node starting (signet sync takes a while)"}


def toggle_wallet():
    """Enable = provision the Ark wallet. Disable = stop showing it, never delete it.

    The wallet can hold signet funds, so 'off' must not be destructive. The db stays on
    disk and re-enabling picks it straight back up.
    """
    st = load_state()
    if enabled("wallet"):
        st["wallet"] = False
        save_state(st)
        return {"ok": True, "running": False,
                "msg": "wallet disabled (data kept at playground-data/bark-templatehash)"}
    if not os.path.exists(os.path.join(BARK_DATADIR, "db.sqlite")):
        Path(BARK_DATADIR).parent.mkdir(parents=True, exist_ok=True)
        r = sh(["bark", "create", "--signet", "--datadir", BARK_DATADIR, "--ark", ARK], timeout=120)
        if r.returncode != 0:
            return {"ok": False, "running": False,
                    "msg": f"wallet creation failed: {(r.stderr or r.stdout)[-400:]}"}
        try:
            os.chmod(os.path.join(BARK_DATADIR, "db.sqlite"), 0o600)
        except Exception:
            pass
    st["wallet"] = True
    save_state(st)
    return {"ok": True, "running": True, "msg": f"Ark wallet ready (server {ARK})"}


def toggle_explorer():
    if running("explorer"):
        stop("explorer")
        return {"ok": True, "running": False, "msg": "explorer stopped"}
    cookie = os.path.join(NODE_DATADIR, "signet", ".cookie")
    if not os.path.exists(cookie):
        return {"ok": False, "running": False,
                "msg": "the inquisition node must be running first (explorer reads its RPC)"}
    env = {
        "BTCEXP_HOST": "127.0.0.1", "BTCEXP_PORT": str(EXPLORER_PORT), "BTCEXP_COIN": "BTC",
        "BTCEXP_BITCOIND_HOST": "127.0.0.1", "BTCEXP_BITCOIND_PORT": "38332",
        "BTCEXP_BITCOIND_COOKIE": cookie, "BTCEXP_ADDRESS_API": "none",
        "BTCEXP_PRIVACY_MODE": "true", "BTCEXP_NO_RATES": "true",
        "BTCEXP_SLOW_DEVICE_MODE": "true",
    }
    log = open(RUNDIR / "explorer.log", "ab")
    p = subprocess.Popen(["btc-rpc-explorer"], stdout=log, stderr=log,
                         env={**ENV, **env}, start_new_session=True)
    pidfile("explorer").write_text(str(p.pid))
    return {"ok": True, "running": True, "msg": f"explorer starting at http://localhost:{EXPLORER_PORT}"}


TOGGLES = {
    "node": toggle_node,
    "wallet": toggle_wallet,
    "eltoo": toggle_eltoo,
    "explorer": toggle_explorer,
}


def run_test(cmd, timeout, name):
    # Bitcoin Core functional-test exit codes: 0 = passed, 1 = failed, 77 = skipped.
    try:
        r = sh(cmd, timeout=timeout)
        out = (r.stdout + r.stderr)
        return {"ok": r.returncode == 0, "skipped": r.returncode == 77, "name": name, "log": out[-4000:]}
    except subprocess.TimeoutExpired:
        return {"ok": False, "skipped": False, "name": name, "log": f"{name} timed out after {timeout}s"}
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "skipped": False, "name": name, "log": f"{name} error: {e}"}


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
        "[components]\nENABLE_WALLET=true\nUSE_SQLITE=true\nUSE_BDB=true\n"
        "ENABLE_CLI=true\nENABLE_BITCOIN_UTIL=true\nENABLE_WALLET_TOOL=true\nENABLE_BITCOIND=true\n"
    )
    logs, all_ok = [], True
    for f, label in BUNDLE_TESTS:
        tmp = RUNDIR / ("bt-" + f)
        subprocess.run(["rm", "-rf", str(tmp)])
        r = run_test(["python3", f"{INQ_SRC}/test/functional/{f}",
                      f"--configfile={cfg}", f"--tmpdir={tmp}", f"--cachedir={RUNDIR}/cache"], 600, f)
        verdict = "PASS" if r["ok"] else ("SKIP" if r.get("skipped") else "FAIL")
        all_ok = all_ok and (r["ok"] or r.get("skipped"))  # a skip is not a failure
        logs.append(f"### {f} — {label}: {verdict}\n{(r['log'] or '')[-1200:]}")
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
        path = self.path.split("?")[0]
        if path.startswith("/api/toggle/"):
            name = path[len("/api/toggle/"):]
            fn = TOGGLES.get(name)
            if not fn:
                self._json({"error": f"unknown component: {name}",
                            "components": list(COMPONENTS)}, 404)
                return
            try:
                self._json(fn())
            except Exception as e:  # noqa: BLE001
                self._json({"ok": False, "msg": str(e)}, 500)
            return
        routes = {
            "/api/eltoo/toggle": toggle_eltoo,   # legacy alias
            "/api/test/eltoo": test_eltoo,
            "/api/test/bundle": test_bundle,
        }
        fn = routes.get(path)
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
    # Component 0 — the Inquisition signet node — is the one thing that comes up on
    # arrival. Everything else (Ark wallet, eltoo, explorer) stays off until toggled.
    if os.environ.get("PLAYGROUND_AUTOSTART_NODE", "1") != "0":
        if start_node():
            print("▶ Component 0: starting bitcoind-inquisition on signet")
        else:
            print("▶ Component 0: inquisition node already running")
    print("▶ Everything else is off. Enable components from the dashboard.")
    url = f"http://localhost:{PORT}"
    if os.environ.get("DISPLAY"):
        subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with http.server.ThreadingHTTPServer((HOST, PORT), Handler) as httpd:
        httpd.serve_forever()


if __name__ == "__main__":
    main()
