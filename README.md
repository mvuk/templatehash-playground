# templatehash-playground

[![ci](https://github.com/mvuk/templatehash-playground/actions/workflows/ci.yml/badge.svg)](https://github.com/mvuk/templatehash-playground/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/mvuk/templatehash-playground)

A one-command, reproducible playground for the **BIP448 bundle** — Taproot-native
*rebindable transactions* (the LNHANCE / CTV+CSFS lineage: `OP_INTERNALKEY`,
`OP_CHECKSIGFROMSTACK`, `OP_TEMPLATEHASH`), testable today on the public **signet** via
[Bitcoin Inquisition](https://github.com/bitcoin-inquisition/bitcoin). Learn about the
bundle at **[github.com/bip448](https://github.com/bip448)**.

Its first hands-on demo puts **Ark covenants** in your hands using `OP_TEMPLATEHASH`
(BIP446 — one opcode of the bundle) via [templatehash.com](https://templatehash.com)'s
Ark server. Further demos, each exercising part of the bundle, plug in as [products](./products).

## Fastest path: hand it to your AI agent

Paste this repo's URL to your coding agent (Claude Code, Cursor, …) and say
**"set this up and run the playground."** It will read [`AGENTS.md`](./AGENTS.md),
install Nix only if your machine needs it, and spin everything up.

## Or run it yourself

```sh
git clone https://github.com/mvuk/templatehash-playground
cd templatehash-playground
./playground
```

`./playground` gets Nix ready (installing it only if necessary — and never touching your
system config) and launches the default product. Then:

```sh
./playground list        # see all products
./playground <name>      # run a specific one
nix run .#default        # if you prefer driving Nix directly
```

No Nix, and don't want it? Use the prebuilt image (published by CI):

```sh
docker run --rm -it -p 4848:4848 ghcr.io/mvuk/templatehash-playground
```

## Funding a wallet

**A templatehash Ark wallet can currently be funded only by _on-chain receive_ or
_Lightning receive_ — not by a faucet VTXO drop.** A VTXO belongs to one specific Ark
server, and the [Second signet faucet](https://signet.2nd.dev)'s Ark (VTXO) option issues
VTXOs on the *covenantless* Ark server (a different server on the same signet), so those
can't land in a templatehash wallet. Fund with one of:

- **On-chain:** get an address with `bark onchain address`, request signet coins for it at
  the faucet (on-chain option), then board into Ark with `bark board --all`.
- **Lightning:** mint an invoice with `bark lightning invoice "100000 sats"` and pay it at
  the faucet (Lightning option) — it settles into a spendable VTXO.

(Automatic funding, and faucet VTXOs issued on the templatehash Ark server, are phase-2
items.)

## Add your own experiment

This is a community playground. Copy [`products/_template/`](./products/_template), edit
it, and open a PR — your experiment becomes `nix run .#<your-name>`. See
[`CONTRIBUTING.md`](./CONTRIBUTING.md).

## Zero-compile & maintainer setup

CI ([`.github/workflows/ci.yml`](./.github/workflows/ci.yml)) builds the flake on Linux and
macOS, runs `nix flake check`, and publishes:
- a **Cachix** cache so `nix run` pulls prebuilt binaries (no compile), and
- a **Docker image** to `ghcr.io/mvuk/templatehash-playground`.

To turn the cache on: create a Cachix cache named `templatehash-playground`, add its
`CACHIX_AUTH_TOKEN` as a repository secret, then add it as a substituter in `flake.nix`'s
`nixConfig` (next to `bark.cachix.org`).

## Status

**Phase 1 (done)** — reproducible `nix run` bundle; bark + templatehash on public signet;
live status dashboard; validated on-chain receive, board→Ark, and Lightning receive.
**Phase 2 (in progress)** — CI + Cachix + Docker + Codespaces (the zero-compile onramp); an
optional Bitcoin Inquisition node module (E).

## License

MIT.
