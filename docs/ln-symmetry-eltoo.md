# LN-Symmetry (eltoo) — mechanism, implementation, demo

**LN-Symmetry** is the modern name for **eltoo** (2018 → renamed ~2023): a way to update a
Lightning channel that replaces the penalty mechanism with a simple "latest state wins"
ratchet. It needs *rebindable* signatures — either `SIGHASH_ANYPREVOUT` (BIP118) or
`OP_CHECKSIGFROMSTACK` + `OP_TEMPLATEHASH` — all of which are
[active on signet](./signet-verification.md).

This is the basis of the playground's **project #2** (`ln-symmetry`).

## Why on Core Lightning (not LDK)

The implementation we build is **Core Lightning (CLN)** — the C implementation — because
that's where Greg Sanders (**instagibbs**) built a *full* eltoo state machine, not a toy. In
the branch you can see whole new subsystems written in C:

- `channeld/eltoo_channeld.c`, `channeld/eltoo_full_channel.c`
- `openingd/eltoo_openingd.c`
- `onchaind/eltoo_onchaind.c`
- `common/initial_eltoo_channel.h`
- `tests/test_eltoo.py` (1,730 lines)

Channel type `"eltoo/even"` sits alongside the normal channel types. This is a real
alternative channel implementation living inside CLN — which is a much stronger artifact than
a spec-only or library sketch.

## How eltoo actually works (read from `test_eltoo.py`)

### 1. Rebinding — the whole point
```python
def bind_eltoo_tx(unbound_tx_hex, funding_txid, funding_outnum):
    """Bind an eltoo transaction's APO input to the funding outpoint."""
```
Eltoo transactions are signed with `SIGHASH_ANYPREVOUT`, so the signature does **not** commit
to which input it spends. The tx is created "unbound" and later *bound* to whatever outpoint
it spends (the funding output, or a previous update's output). That rebinding is the thing APO
exists for. Classic Lightning (Poon–Dryja) can't do this — each state's tx is nailed to one
prior output, which is why it needs **penalty transactions** and asymmetric per-state keys.

### 2. The update + settle ratchet (why it's "symmetry")
Each channel state is a **pair** of transactions:
- **update tx** — spends the funding output (or a *previous* update's output) via APO;
- **settle tx** — spends the update tx after a **CSV challenge delay**, paying out balances
  (and HTLCs).

Because signatures rebind, **a newer state's update can always spend an older state's update
output**, enforced by a state-number ratchet (`nLockTime`/`nSequence`). Both parties hold the
**same** transactions — *symmetric*, no penalty keys, no "who cheated" bookkeeping. Publish an
old state and your counterparty simply publishes a newer update on top. Hence *LN-Symmetry*.

### 3. Zero-fee txs + ephemeral anchors (P2A) + CPFP
```python
def broadcast_eltoo_tx_with_cpfp(bitcoind, tx_hex):
    """...ephemeral anchors that have 0 fees ... Bitcoin Inquisition has special
       handling for ephemeral anchors (P2A)."""
```
Update/settle txs carry **0 fees** and a **P2A ephemeral anchor** output; fees are attached at
broadcast time via a **CPFP child in the same package**. This is why the demo uses package
submission, and why the Inquisition node (with ephemeral-anchor + package relay handling) is
required.

### 4. The lifecycle the tests exercise (= the demo runbook)
- `test_eltoo_tx_binding` — the APO binding mechanism.
- `test_eltoo_*_reestablishment` (×5) — resync channel state after reconnect.
- `test_eltoo_unannounced_hop` — **payments routed** over eltoo channels.
- `test_eltoo_htlc` — HTLC resolved on-chain via `eltoo_onchaind` (broadcasts `update_tx` +
  CPFP).
- `test_eltoo_restart_*` (×4) — **state survives restarts** — this Jan-2026 branch fixed the
  "can't restart the node" wart of the older `eltoo_support` branch.
- `test_eltoo_close_simple` — cooperative mutual close.

## The implementation we build

- **Repo/branch:** `github.com/instagibbs/lightning` @ `2026-01-eltoo_templatehash`
  (rev `c7710830`, dated 2026-01-23) — HEAD commit *"OP_TEMPLATEHASH migration compiles,
  passes unit test"*, i.e. the CSFS/TEMPLATEHASH-route eltoo (on-brand for this playground).
- **Submodules:** it pulls **instagibbs' fork of `libwally-core`** (with the APO/annex
  support), plus `jsmn`, `libbacktrace`, `gheap`.
- **Nix packaging:** `pkgs.clightning.overrideAttrs` swapping `src` for the branch
  (`fetchSubmodules = true`) and adding `--enable-experimental-features`. nixpkgs already knows
  how to build CLN (autoconf + gettext + python/mako + libsodium/gmp/sqlite/zlib), and the
  branch bundles its own libwally via submodule.
- Other branches of interest: `eltoo_rebased` / `eltoo_support` (older, **APO route**;
  `eltoo_support` cannot restart the node), `elements_eltoo_support`.

## The demo runbook (against our local signet node)

1. `bitcoind-inquisition -signet -txindex -addnode=inquisition.bitcoin-signet.net` (this
   repo's node; we keep a synced datadir at height 315,083).
2. Two eltoo `lightningd` nodes in developer mode with `experimental-anchors`, network signet,
   pointed at the bitcoind RPC.
3. Fund node 1 from the [Second signet faucet](https://signet.2nd.dev).
4. `l1 fundchannel <l2-id> …` — opens an **eltoo/even** channel.
5. Make a payment → new update/settle pair.
6. Force-close: pull `last_update_tx` from `listpeers`, `bind` it to the funding outpoint,
   `sendrawtransaction` **as a package** with a CPFP child paying the ephemeral anchor.
7. After the CSV challenge delay, broadcast `last_settlement_tx` (also CPFP).
8. Observe the balances settle on-chain — **a real LN-Symmetry channel resolving on the public
   signet.**

## Status

Consensus layer: verified live on signet (see [signet-verification](./signet-verification.md)).
Application layer: the CLN eltoo binary is being built and wired into this flake as
`packages.clightning-eltoo` + `products/ln-symmetry`. Because it depends on unmerged PoC
branches and package/CPFP mechanics, treat it as an **experiment**, not production.
