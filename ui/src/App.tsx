import { useEffect, useState } from "react";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import {
  Droplets, Zap, TerminalSquare, ExternalLink, BookOpen, Layers,
  Loader2, CheckCircle2, XCircle, FlaskConical, Search, Wallet,
} from "lucide-react";

type Check = { ok: boolean; detail?: string };
type NodeInfo = { blocks?: number; headers?: number; progress?: number; ibd?: boolean };
type Component = "node" | "wallet" | "eltoo" | "explorer";
type Status = {
  enabled?: Record<Component, boolean>;
  node?: NodeInfo;
  explorer?: { ok: boolean; url?: string };
  ark?: Check; wallet?: Check; esplora?: Check; faucet?: Check;
  spendable_sat?: number | string; vtxo?: string; onchain?: string;
  ln_running?: boolean; node_running?: boolean; updated?: string;
};
type TestResult = { ok: boolean; name?: string; log?: string };

const FAUCET = "https://signet.2nd.dev";
const BUNDLE = "https://github.com/bip448";
const REPO = "https://github.com/mvuk/templatehash-playground";

const BUNDLE_TESTS = [
  { file: "feature_checktemplateverify.py", op: "OP_CHECKTEMPLATEVERIFY (CTV, BIP119)" },
  { file: "feature_templatehash.py", op: "OP_TEMPLATEHASH (BIP446)" },
  { file: "feature_taproot.py", op: "OP_CHECKSIGFROMSTACK (BIP348) · OP_INTERNALKEY (BIP349) · TEMPLATEHASH" },
];

function Dot({ ok }: { ok?: boolean }) {
  return (
    <span
      className={`inline-block h-2.5 w-2.5 rounded-full ${ok ? "bg-emerald-500" : "bg-rose-500"}`}
      style={{ boxShadow: `0 0 0 3px ${ok ? "rgba(16,185,129,.18)" : "rgba(244,63,94,.18)"}` }}
    />
  );
}

function Num({ n }: { n: number }) {
  return (
    <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-primary text-sm font-bold text-primary-foreground">
      {n}
    </span>
  );
}

function TestPanel({
  label, hint, busy, result, onRun,
}: { label: string; hint?: string; busy: boolean; result?: TestResult; onRun: () => void }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="mt-3 border-t pt-3">
      <div className="flex flex-wrap items-center gap-3">
        <Button variant="outline" size="sm" onClick={onRun} disabled={busy}>
          {busy ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <FlaskConical className="h-3.5 w-3.5" />}
          {label}
        </Button>
        {busy && hint && <span className="text-xs text-muted-foreground">{hint}</span>}
        {result && !busy && (
          <Badge variant="outline" className="gap-1.5">
            {result.ok ? <CheckCircle2 className="h-3.5 w-3.5 text-emerald-500" /> : <XCircle className="h-3.5 w-3.5 text-rose-500" />}
            {result.ok ? "passed" : "failed"}
          </Badge>
        )}
        {result && !busy && (
          <button className="text-xs text-muted-foreground underline" onClick={() => setOpen((o) => !o)}>
            {open ? "hide log" : "show log"}
          </button>
        )}
      </div>
      {open && result?.log && (
        <pre className="mt-2 max-h-56 overflow-auto rounded-md border bg-muted p-3 font-mono text-[11px] leading-relaxed text-muted-foreground">
          {result.log}
        </pre>
      )}
    </div>
  );
}

export default function App() {
  const [s, setS] = useState<Status>({});
  const [busy, setBusy] = useState<{ [k: string]: boolean }>({});
  const [res, setRes] = useState<{ [k: string]: TestResult }>({});
  // per-component toggle spinners, so switching the explorer doesn't grey out eltoo
  const [toggling, setToggling] = useState<Partial<Record<Component, boolean>>>({});

  const load = () =>
    fetch("./status.json", { cache: "no-store" }).then((r) => r.json()).then(setS).catch(() => {});
  useEffect(() => {
    load();
    const t = setInterval(load, 15000);
    return () => clearInterval(t);
  }, []);

  const post = (path: string) => fetch(path, { method: "POST" }).then((r) => r.json());

  const runTest = async (key: string, path: string) => {
    setBusy((b) => ({ ...b, [key]: true }));
    try {
      const result = await post(path);
      setRes((r) => ({ ...r, [key]: result }));
    } catch (e) {
      setRes((r) => ({ ...r, [key]: { ok: false, log: String(e) } }));
    } finally {
      setBusy((b) => ({ ...b, [key]: false }));
    }
  };

  // Every component is opt-in. Nothing here runs until its switch is flipped.
  const on = (c: Component) => !!s.enabled?.[c];
  const toggle = async (c: Component) => {
    setToggling((t) => ({ ...t, [c]: true }));
    try { await post(`/api/toggle/${c}`); } catch { /* ignore */ }
    await load();
    setToggling((t) => ({ ...t, [c]: false }));
  };

  const Toggle = ({ c }: { c: Component }) => (
    <div className="ml-auto flex items-center gap-2">
      <span className="flex items-center gap-1.5 text-xs text-muted-foreground">
        {toggling[c] ? <Loader2 className="h-3 w-3 animate-spin" /> : <Dot ok={on(c)} />}
        {toggling[c] ? "…" : on(c) ? "running" : "off"}
      </span>
      <Switch checked={on(c)} disabled={!!toggling[c]} onCheckedChange={() => toggle(c)} />
    </div>
  );

  return (
    <div className="mx-auto max-w-2xl px-5 py-10">
      <header className="mb-6">
        <h1 className="text-2xl font-bold tracking-tight">templatehash playground</h1>
        <p className="mt-1.5 text-muted-foreground">
          A hands-on environment for the <b className="text-foreground">BIP448 bundle</b> — Taproot-native
          rebindable transactions (covenants + eltoo) — on the{" "}
          <b className="text-foreground">Bitcoin Inquisition signet</b>, in a{" "}
          <b className="text-foreground">Nix environment on this machine</b>. Built up from the foundation:
        </p>
      </header>

      <a href={FAUCET} target="_blank" rel="noopener noreferrer">
        <Button className="w-full" size="lg">
          <Droplets className="h-4 w-4" /> Faucet — get signet test coins (signet.2nd.dev)
        </Button>
      </a>

      <h2 className="mb-3 mt-8 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
        The stack — foundation first
      </h2>

      {/* 0 — Foundation: the Inquisition node itself. The only thing running on arrival. */}
      <Card className="mb-4">
        <CardHeader>
          <div className="flex items-center gap-3">
            <Num n={0} />
            <CardTitle className="text-base"><Layers className="mr-1 inline h-4 w-4 -translate-y-0.5" />Bitcoin Inquisition node</CardTitle>
            <Toggle c="node" />
          </div>
          <CardDescription className="pt-2">
            The foundation, and the one component that starts with the playground. A{" "}
            <code>bitcoind-inquisition</code> node on the public <b className="text-foreground">signet</b>,
            enforcing the BIP448 opcodes. Everything below is off until you switch it on.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="rounded-md border bg-secondary/40 p-3">
            {on("node") ? (
              <>
                <div className="flex flex-wrap items-center gap-x-4 gap-y-1.5 text-sm text-muted-foreground">
                  <span className="flex items-center gap-1.5">
                    <Dot ok={!s.node?.ibd} />
                    {s.node?.ibd ? "syncing" : "synced"}
                  </span>
                  <span>
                    block <b className="text-foreground">{s.node?.blocks?.toLocaleString() ?? "…"}</b>
                    {s.node?.headers ? ` / ${s.node.headers.toLocaleString()}` : ""}
                  </span>
                </div>
                <div className="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-secondary">
                  <div className="h-full bg-primary transition-all" style={{ width: `${s.node?.progress ?? 0}%` }} />
                </div>
                <div className="mt-1 text-xs text-muted-foreground">{s.node?.progress ?? 0}% verified</div>
              </>
            ) : (
              <div className="text-sm text-muted-foreground">Node is off — switch it on to connect to signet.</div>
            )}
          </div>
          <div className="mt-3 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
            Consensus opcodes this node enforces
          </div>
          <ul className="mt-1.5 space-y-1.5 text-sm">
            {BUNDLE_TESTS.map((t) => (
              <li key={t.file} className="flex flex-col">
                <code className="text-[13px] text-foreground">{t.file}</code>
                <span className="text-xs text-muted-foreground">{t.op}</span>
              </li>
            ))}
          </ul>
          <TestPanel
            label="Verify bundle tests pass"
            hint="running 3 consensus suites — this takes a few minutes"
            busy={!!busy.bundle}
            result={res.bundle}
            onRun={() => runTest("bundle", "/api/test/bundle")}
          />
        </CardContent>
      </Card>

      {/* 1 — LN-Symmetry (eltoo) */}
      <Card className="mb-4">
        <CardHeader>
          <div className="flex items-center gap-3">
            <Num n={1} />
            <CardTitle className="text-base"><Zap className="mr-1 inline h-4 w-4 -translate-y-0.5" />LN-Symmetry (eltoo)</CardTitle>
            <Toggle c="eltoo" />
          </div>
          <CardDescription className="pt-2">
            Rebindable Lightning channels (eltoo): a symmetric “latest-state-wins” ratchet with{" "}
            <b className="text-foreground">no penalty transactions</b>, via <code>ANYPREVOUT</code> /{" "}
            <code>CSFS</code>+<code>TEMPLATEHASH</code>. The eltoo <code>lightningd</code> runs here on your machine.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <pre className="rounded-md border bg-secondary/60 px-3 py-2 text-[13px]"><TerminalSquare className="mr-2 inline h-3.5 w-3.5" />./playground ln-symmetry</pre>
          <TestPanel label="Verify eltoo tests pass" busy={!!busy.eltoo} result={res.eltoo} onRun={() => runTest("eltoo", "/api/test/eltoo")} />
        </CardContent>
      </Card>

      {/* 2 — templatehash Ark (bark) */}
      <Card className="mb-4">
        <CardHeader>
          <div className="flex items-center gap-3">
            <Num n={2} />
            <CardTitle className="text-base"><Wallet className="mr-1 inline h-4 w-4 -translate-y-0.5" />templatehash Ark (bark)</CardTitle>
            <Toggle c="wallet" />
          </div>
          <CardDescription className="pt-2">
            A covenant Ark wallet built on <code>OP_TEMPLATEHASH</code> (verified in 0). This runs only the{" "}
            <b className="text-foreground">bark client</b> (a one-shot CLI wallet, invoked per command — not a
            daemon). We do <b className="text-foreground">not</b> run the Ark server: <code>captaind</code> and
            the <code>watchmand</code> watchtower run remotely at <code>ark.templatehash.com</code>.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <pre className="rounded-md border bg-secondary/60 px-3 py-2 text-[13px]"><TerminalSquare className="mr-2 inline h-3.5 w-3.5" />./playground bark-templatehash</pre>
          <div className="rounded-md border bg-secondary/40 p-3">
            {on("wallet") ? (
              <>
                <div className="mb-2 text-xs font-semibold uppercase tracking-wider text-muted-foreground">This bark client's wallet</div>
                <div className="flex flex-wrap items-center gap-x-4 gap-y-1.5 text-sm text-muted-foreground">
                  <span className="flex items-center gap-1.5"><Dot ok={s.ark?.ok} /> server {s.ark?.detail ?? "…"}</span>
                  <span className="flex items-center gap-1.5"><Dot ok={s.esplora?.ok} /> chain {s.esplora?.detail ?? "…"}</span>
                  <span className="flex items-center gap-1.5"><Dot ok={s.faucet?.ok} /> faucet</span>
                </div>
                <div className="mt-2 text-2xl font-bold text-foreground">{s.spendable_sat ?? "…"} <span className="text-sm font-normal text-muted-foreground">sat spendable</span></div>
                <div className="mt-2 space-y-1 font-mono text-[11px] leading-relaxed text-muted-foreground">
                  <div className="break-all">VTXO: {s.vtxo ?? "…"}</div>
                  <div className="break-all">on-chain: {s.onchain ?? "…"}</div>
                </div>
              </>
            ) : (
              <div className="text-sm text-muted-foreground">
                No wallet yet. Switching this on creates a signet Ark wallet at{" "}
                <code className="text-[12px]">playground-data/bark-templatehash</code> against{" "}
                <code className="text-[12px]">ark.templatehash.com</code>. Switching it back off keeps the
                wallet on disk — it is never deleted.
              </div>
            )}
          </div>
        </CardContent>
      </Card>

      {/* 3 — Block explorer (btc-rpc-explorer), reads the node's RPC. Off by default. */}
      <Card className="mb-4">
        <CardHeader>
          <div className="flex items-center gap-3">
            <Num n={3} />
            <CardTitle className="text-base"><Search className="mr-1 inline h-4 w-4 -translate-y-0.5" />Block explorer</CardTitle>
            <Toggle c="explorer" />
          </div>
          <CardDescription className="pt-2">
            A local <code>btc-rpc-explorer</code> reading straight from component 0's RPC — no database,
            no electrum server, nothing duplicated on disk. Browse blocks, transactions, the mempool and
            fees on your own node.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {on("explorer") ? (
            <a href={s.explorer?.url ?? "http://localhost:3002"} target="_blank" rel="noopener noreferrer">
              <Button variant="outline" className="w-full">
                <ExternalLink className="h-4 w-4" /> Open explorer — {s.explorer?.url ?? "http://localhost:3002"}
              </Button>
            </a>
          ) : (
            <div className="text-sm text-muted-foreground">
              Off. Needs the node running, since every query is answered from its <code>-txindex</code>.
              Address lookups stay disabled — those would require an electrum backend.
            </div>
          )}
        </CardContent>
      </Card>

      <div className="mt-5 flex gap-3">
        <a href={BUNDLE} target="_blank" rel="noopener noreferrer" className="flex-1"><Button variant="outline" className="w-full"><BookOpen className="h-4 w-4" /> BIP448 bundle</Button></a>
        <a href={REPO} target="_blank" rel="noopener noreferrer" className="flex-1"><Button variant="outline" className="w-full"><ExternalLink className="h-4 w-4" /> Repo &amp; docs</Button></a>
      </div>

      <p className="mt-6 text-center text-xs text-muted-foreground">Bitcoin Inquisition signet · updated {s.updated ?? "…"} · auto-refresh 15s</p>
    </div>
  );
}
