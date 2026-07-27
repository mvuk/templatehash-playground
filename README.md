# templatehash-playground

A one-command, reproducible playground for the **BIP448 bundle** — Taproot-native
*rebindable transactions* (the LNHANCE / CTV+CSFS lineage: `OP_INTERNALKEY`,
`OP_CHECKSIGFROMSTACK`, `OP_TEMPLATEHASH`), testable today on the public **signet** via
[Bitcoin Inquisition](https://github.com/bitcoin-inquisition/bitcoin). Learn about the
bundle at **[github.com/bip448](https://github.com/bip448)**.

Its first hands-on demo puts **Ark covenants** in your hands using `OP_TEMPLATEHASH`
(BIP446 — one opcode of the bundle) via [templatehash.com](https://templatehash.com)'s
ASP. Further demos, each exercising part of the bundle, plug in as [products](./products).

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

## Funding a wallet

Fund your signet wallet at the [Second signet faucet](https://signet.2nd.dev) — on-chain,
over Lightning, or as an Ark VTXO. (Automatic faucet funding is a phase-2 feature.)

## Add your own experiment

This is a community playground. Copy [`products/_template/`](./products/_template), edit
it, and open a PR — your experiment becomes `nix run .#<your-name>`. See
[`CONTRIBUTING.md`](./CONTRIBUTING.md).

## Status

**Phase 1** — reproducible `nix run` bundle, bark + templatehash on public signet.
**Phase 2 (planned)** — Cachix + prebuilt Docker image (zero compile), "Open in Codespaces"
button, faucet-API auto-funding, and an optional Bitcoin Inquisition node module.

## License

MIT.
