# templatehash-playground

[![ci](https://github.com/mvuk/templatehash-playground/actions/workflows/ci.yml/badge.svg)](https://github.com/mvuk/templatehash-playground/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/mvuk/templatehash-playground)

A one-command, reproducible playground for the **BIP448 bundle** — Taproot-native
*rebindable transactions* (the LNHANCE / CTV+CSFS lineage: `OP_INTERNALKEY`,
`OP_CHECKSIGFROMSTACK`, `OP_TEMPLATEHASH`), testable today on the public **signet** via
[Bitcoin Inquisition](https://github.com/bitcoin-inquisition/bitcoin). Learn about the
bundle at **[github.com/bip448](https://github.com/bip448)**.

It's a registry of independent [projects](./products), each demoing part of the bundle on
signet — ordered oldest-tech-first: **LN-Symmetry (eltoo)** on Core Lightning, then **Ark
covenants** via `OP_TEMPLATEHASH`. More plug in as the bundle's other pieces get exercised.

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

`./playground` gets Nix ready — installing it only if necessary (via the Determinate
installer), and using per-command flags instead of editing any existing Nix config — then
launches the default product: a live **status dashboard at http://localhost:4848**. Then:

```sh
./playground list        # see all products
./playground <name>      # run a specific one
nix run .#default        # if you prefer driving Nix directly
nix run .#node           # (Linux) run a local Bitcoin Inquisition signet node
```

No Nix, and don't want it? Use the prebuilt image (published by CI):

```sh
docker run --rm -it -p 4848:4848 ghcr.io/mvuk/templatehash-playground
```

## Projects

The playground is a registry of independent projects (`./playground list`), **ordered
oldest-tech-first**:

1. **`ln-symmetry`** — **LN-Symmetry (eltoo)** on Core Lightning (instagibbs' fork), built
   reproducibly: the eltoo `lightningd` + its three eltoo subdaemons. eltoo replaces
   Lightning's penalty transactions with a symmetric *latest-state-wins* ratchet, using
   rebindable `update`+`settle` txs (`ANYPREVOUT`, or `CSFS`+`TEMPLATEHASH`). *(Linux.)*
   `nix run .#ln-symmetry` shows the node + the runbook for a live signet channel.
2. **`bark-templatehash`** — a covenant-enabled **bark client** (Ark wallet) exercising
   `OP_TEMPLATEHASH`.
   > Runs the bark **client** pointed at the **hosted** Ark server `ark.templatehash.com`;
   > it does **not** run a `captaind` of your own.

Deep dives for both live in [`docs/`](./docs). Adding the next project is a PR: copy
[`products/_template/`](./products/_template) — see
[Add your own experiment](#add-your-own-experiment).

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

## Zero-compile

CI ([`.github/workflows/ci.yml`](./.github/workflows/ci.yml)) builds the flake on Linux and
macOS on every push and publishes two prebuilt paths, so nobody has to compile:
- a **Cachix** cache ([`templatehash-playground.cachix.org`](https://app.cachix.org/cache/templatehash-playground)),
  already wired into the flake — `nix run` / `./playground` pull prebuilt binaries, and
- a **Docker image** at `ghcr.io/mvuk/templatehash-playground`.

Forking? Point CI at your own cache: create a Cachix cache, add its `CACHIX_AUTH_TOKEN`
secret, and swap the substituter + key in `flake.nix`'s `nixConfig`.

## Status

**Two projects, reproducible.** `ln-symmetry` (eltoo Core Lightning — `lightningd` + eltoo
subdaemons, its eltoo settle-tx unit test run in the build) and `bark-templatehash` (Ark
covenant client). A `bitcoind-inquisition` node (`.#node`) + `nixosModules.inquisition-node`
(destined for nix-bitcoin). All five bundle opcodes **verified `active` on the live signet**
(see [`docs/signet-verification.md`](./docs/signet-verification.md)). CI (Linux + macOS) +
Cachix + Docker + Codespaces zero-compile onramp; live status dashboard for the bark demo.

**Next** — a fully-automated two-node eltoo channel demo on signet (the CLN integration
harness needs its non-NixOS container), faucet auto-funding, and more bundle demos as
`products/`.

## License

MIT.
