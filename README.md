# templatehash-playground

A one-command, reproducible playground for **OP_TEMPLATEHASH (BIP446)** — the covenant
opcode behind [templatehash.com](https://templatehash.com). It builds an
[Ark](https://second.tech) wallet (the `bark` client) on the public **signet**, pointed
at the covenant ASP `ark.templatehash.com`, so you can try covenants live.

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
