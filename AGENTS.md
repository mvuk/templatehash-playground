# AGENTS.md — runbook for LLM agents

You are most likely an AI coding agent (Claude Code, Cursor, etc.) that a human
pointed at this repository so you can **spin up a working BIP448-bundle playground for
them** (first demo: OP_TEMPLATEHASH covenants via Ark). This file is your instruction
set. Follow it top to bottom.

`CLAUDE.md` is a symlink to this file.

## What this is

A one-command, reproducible playground for the **BIP448 bundle** — Taproot-native
rebindable transactions (`OP_INTERNALKEY`, `OP_CHECKSIGFROMSTACK`, `OP_TEMPLATEHASH`),
tested on the public signet via Bitcoin Inquisition. Learn about the bundle at
[github.com/bip448](https://github.com/bip448).

Product #1 is an **Ark wallet** (the `bark` client) demonstrating `OP_TEMPLATEHASH`
(BIP446), on the **public signet** pointed at the covenant ASP `ark.templatehash.com`.
The whole thing is a Nix flake, so it builds the same everywhere. Future products
exercise other parts of the bundle.

## The one command

```sh
./playground
```

That's it. The `./playground` script makes Nix ready (installing it only if needed),
then launches the default product. To pick a product: `./playground <name>`; to see
them: `./playground list`.

If you'd rather drive Nix yourself: `nix run .#default` (add
`--extra-experimental-features 'nix-command flakes'` if this machine hasn't enabled
them).

## The Nix-readiness ladder (what `./playground` does, so you understand it)

Advance the machine only as far as needed. **Never** mutate the user's system config;
prefer per-command flags. **Never** run a Nix installer on NixOS.

| You detect… | Do this |
|---|---|
| `nix` runs and `nix … eval` with flakes succeeds | Nothing — it's ready. Run the flake. |
| `nix` installed but **not on PATH** | Source `~/.nix-profile/etc/profile.d/nix.sh` or `/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`, retry. |
| `nix` present, **flakes not enabled** in config | Don't edit config — pass `--extra-experimental-features 'nix-command flakes'` on each invocation. |
| **On NixOS** and nix unusable | Do **not** install. Tell the user to add `nix.settings.experimental-features = [ "nix-command" "flakes" ];` and rebuild. |
| **No Nix**, has sudo, not NixOS | Install with the Determinate installer: `curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \| sh -s -- install --no-confirm`, source the profile, retry. |
| **No Nix**, no sudo | Explain the limitation. A prebuilt Docker image is the phase-2 fallback (not published yet). |

Always finish with a smoke test — `nix … eval --raw --expr '"ok"'` — so "installed"
is never mistaken for "working."

### Detection snippets
```sh
command -v nix                                   # on PATH?
[ -e /etc/NIXOS ] || [ -d /run/current-system ]  # NixOS?
sudo -n true 2>/dev/null                          # passwordless sudo?
command -v docker && docker info >/dev/null 2>&1  # docker fallback available?
nix --extra-experimental-features 'nix-command flakes' eval --raw --expr '"ok"'  # works?
```

### Nix present but broken
If `nix` exists but the smoke test fails: likely the daemon is down
(`sudo launchctl kickstart -k system/org.nixos.nix-daemon` on macOS, or
`sudo systemctl restart nix-daemon` on Linux), or the install is too old for flakes
(upgrade, or use the Determinate installer to repair). Report the specific error to
the user rather than looping.

## After it's running — drive the demo

1. The default product creates a signet wallet at `./playground-data/bark-templatehash`,
   pointed at `ark.templatehash.com`.
2. **Funding (manual in phase 1):** get a receive address from the wallet and fund it at
   <https://signet.2nd.dev> (on-chain or as an Ark VTXO). The faucet HTTP API exists
   (`POST /api/v1/faucet/{ark,bitcoin,lightning}`) but is **not wired in yet** — its Ark
   endpoint currently targets a different ASP.
3. Explain to the human what they're seeing: OP_TEMPLATEHASH lets an output commit to
   its spending transaction (a covenant); Ark uses it so VTXOs don't need pre-signed
   transactions. This wallet is that, live, on signet.

## Products & contributing
Each `products/<name>/product.nix` returning `{ description; app; }` becomes
`nix run .#<name>`. To add your own experiment, copy `products/_template/`, edit it,
and open a PR — see `CONTRIBUTING.md`.
