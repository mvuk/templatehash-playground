import { useEffect, useState } from "react";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Droplets, Zap, TerminalSquare, ExternalLink, BookOpen } from "lucide-react";

type Check = { ok: boolean; detail?: string };
type Status = {
  ark?: Check;
  wallet?: Check;
  esplora?: Check;
  faucet?: Check;
  spendable_sat?: number | string;
  vtxo?: string;
  onchain?: string;
  ln_running?: boolean;
  updated?: string;
};

const FAUCET = "https://signet.2nd.dev";
const BUNDLE = "https://github.com/bip448";
const REPO = "https://github.com/mvuk/templatehash-playground";

function Dot({ ok }: { ok?: boolean }) {
  return (
    <span
      className={`inline-block h-2.5 w-2.5 rounded-full ${ok ? "bg-emerald-500" : "bg-rose-500"}`}
      style={{ boxShadow: `0 0 0 3px ${ok ? "rgba(16,185,129,.18)" : "rgba(244,63,94,.18)"}` }}
    />
  );
}

export default function App() {
  const [s, setS] = useState<Status>({});
  useEffect(() => {
    const load = () =>
      fetch("./status.json", { cache: "no-store" })
        .then((r) => r.json())
        .then(setS)
        .catch(() => {});
    load();
    const t = setInterval(load, 15000);
    return () => clearInterval(t);
  }, []);

  return (
    <div className="mx-auto max-w-2xl px-5 py-10">
      <header className="mb-6">
        <h1 className="text-2xl font-bold tracking-tight">templatehash playground</h1>
        <p className="mt-1.5 text-muted-foreground">
          A hands-on environment for the <b className="text-foreground">BIP448 bundle</b> — Taproot-native
          rebindable transactions (covenants + eltoo) — running on the{" "}
          <b className="text-foreground">Bitcoin Inquisition signet</b>. The projects below live in a{" "}
          <b className="text-foreground">Nix environment on this machine</b>; pick one.
        </p>
      </header>

      <a href={FAUCET} target="_blank" rel="noopener noreferrer">
        <Button className="w-full" size="lg">
          <Droplets className="h-4 w-4" /> Faucet — get signet test coins (signet.2nd.dev)
        </Button>
      </a>

      <h2 className="mb-3 mt-8 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
        Projects
      </h2>

      {/* Project 1 — LN-Symmetry (eltoo) */}
      <Card className="mb-4">
        <CardHeader>
          <div className="flex items-center gap-3">
            <span className="flex h-6 w-6 items-center justify-center rounded-full bg-primary text-sm font-bold text-primary-foreground">
              1
            </span>
            <CardTitle className="text-base">
              <Zap className="mr-1 inline h-4 w-4 -translate-y-0.5" />
              LN-Symmetry (eltoo)
            </CardTitle>
            <Badge variant={s.ln_running ? "secondary" : "outline"} className="ml-auto gap-1.5">
              <Dot ok={s.ln_running} /> {s.ln_running ? "running locally" : "stopped"}
            </Badge>
          </div>
          <CardDescription className="pt-2">
            Rebindable Lightning channels (eltoo): a symmetric “latest-state-wins” ratchet with{" "}
            <b className="text-foreground">no penalty transactions</b>, via <code>ANYPREVOUT</code> /{" "}
            <code>CSFS</code>+<code>TEMPLATEHASH</code>. The eltoo <code>lightningd</code> runs here on your
            machine (not a remote service).
          </CardDescription>
        </CardHeader>
        <CardContent>
          <pre className="rounded-md border bg-secondary/60 px-3 py-2 text-[13px]">
            <TerminalSquare className="mr-2 inline h-3.5 w-3.5" />./playground ln-symmetry
          </pre>
        </CardContent>
      </Card>

      {/* Project 2 — templatehash Ark (bark) */}
      <Card className="mb-4">
        <CardHeader>
          <div className="flex items-center gap-3">
            <span className="flex h-6 w-6 items-center justify-center rounded-full bg-primary text-sm font-bold text-primary-foreground">
              2
            </span>
            <CardTitle className="text-base">templatehash Ark (bark)</CardTitle>
            <Badge variant={s.ark?.ok ? "secondary" : "outline"} className="ml-auto gap-1.5">
              <Dot ok={s.ark?.ok} /> server {s.ark?.detail ?? "…"}
            </Badge>
          </div>
          <CardDescription className="pt-2">
            A covenant Ark wallet using <code>OP_TEMPLATEHASH</code>. This runs only the{" "}
            <b className="text-foreground">bark client</b> (a one-shot CLI wallet, invoked per command — not a
            daemon). We do <b className="text-foreground">not</b> run the Ark server: <code>captaind</code> and
            the <code>watchmand</code> watchtower run remotely at <code>ark.templatehash.com</code>.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <pre className="rounded-md border bg-secondary/60 px-3 py-2 text-[13px]">
            <TerminalSquare className="mr-2 inline h-3.5 w-3.5" />./playground bark-templatehash
          </pre>
          <div className="rounded-md border bg-secondary/40 p-3">
            <div className="mb-2 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              This bark client's wallet
            </div>
            <div className="flex flex-wrap items-center gap-x-4 gap-y-1.5 text-sm text-muted-foreground">
              <span className="flex items-center gap-1.5"><Dot ok={s.wallet?.ok} /> wallet {s.wallet?.detail ?? "…"}</span>
              <span className="flex items-center gap-1.5"><Dot ok={s.esplora?.ok} /> chain {s.esplora?.detail ?? "…"}</span>
              <span className="flex items-center gap-1.5"><Dot ok={s.faucet?.ok} /> faucet</span>
            </div>
            <div className="mt-2 text-2xl font-bold text-foreground">
              {s.spendable_sat ?? "…"} <span className="text-sm font-normal text-muted-foreground">sat spendable</span>
            </div>
            <div className="mt-2 space-y-1 font-mono text-[11px] leading-relaxed text-muted-foreground">
              <div className="break-all">VTXO: {s.vtxo ?? "…"}</div>
              <div className="break-all">on-chain: {s.onchain ?? "…"}</div>
            </div>
          </div>
        </CardContent>
      </Card>

      <div className="mt-5 flex gap-3">
        <a href={BUNDLE} target="_blank" rel="noopener noreferrer" className="flex-1">
          <Button variant="outline" className="w-full"><BookOpen className="h-4 w-4" /> BIP448 bundle</Button>
        </a>
        <a href={REPO} target="_blank" rel="noopener noreferrer" className="flex-1">
          <Button variant="outline" className="w-full"><ExternalLink className="h-4 w-4" /> Repo &amp; docs</Button>
        </a>
      </div>

      <p className="mt-6 text-center text-xs text-muted-foreground">
        Bitcoin Inquisition signet · updated {s.updated ?? "…"} · auto-refresh 15s
      </p>
    </div>
  );
}
