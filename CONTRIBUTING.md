# Contributing a product

The playground is a registry of small, self-contained experiments. Adding one is a PR.

## Steps

1. Copy the template:
   ```sh
   cp -r products/_template products/my-experiment
   ```
2. Edit `products/my-experiment/product.nix`:
   - set a one-line `description`,
   - make `app` a `pkgs.writeShellApplication` that does your demo.
   You get `pkgs`, `lib`, and the built `bark-cli` (its binary is `bark`).
3. Test it:
   ```sh
   ./playground my-experiment
   # or: nix run .#my-experiment
   ```
4. Open a PR. The flake auto-discovers `products/<name>/product.nix`, so once merged it's
   live as `nix run .#my-experiment` and shows up in `./playground list`.

## Guidelines

- **Keep it self-contained and idempotent** — safe to run twice. Write runtime state under
  `./playground-data/<name>/` (git-ignored).
- **Public signet only** for now. Point Ark products at `ark.templatehash.com` explicitly —
  bark's `--signet` default Ark server is a *different* server.
- **No secrets in the repo.** Read config from env vars with sensible defaults.
- Prefer adding runtime tools via `runtimeInputs` rather than assuming they're on PATH.
