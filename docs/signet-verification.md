# Signet verification — proving it against the node, not the docs

This documents the **empirical** verification: that our built node *enforces* the bundle
opcodes (by running its own consensus tests), and that those opcodes are **active on the live
public signet** (by syncing and querying `getdeploymentinfo`).

All commands below were actually run. The node is `packages.bitcoind-inquisition`
(**Bitcoin Inquisition v29.4.0**, a fork of Bitcoin Core 29.x), pinned in this repo's flake to
`bitcoin-inquisition/bitcoin@3db09a1b` (branch `29.x`), based on `nixos-25.05`'s bitcoind 29.0.

## 1. The node builds and reports as Inquisition

```
$ nix build .#bitcoind-inquisition
$ ./result/bin/bitcoind -version | head -1
Bitcoin Inquisition daemon version v29.4.0
```

The interpreter (`src/script/interpreter.cpp`) contains `SIGHASH_ANYPREVOUT`,
`OP_CHECKSIGFROMSTACK`, `OP_CHECKTEMPLATEVERIFY`, `OP_INTERNALKEY`, `OP_TEMPLATEHASH`.

## 2. Running the node's own consensus tests (proves *enforcement*)

The functional-test framework finds binaries via a build-generated `config.ini`. For a Nix
build we synthesize one pointing `BUILDDIR` at the package (binaries live in `BUILDDIR/bin`):

```ini
[environment]
SRCDIR=/nix/store/…-source                 # the inquisition source
BUILDDIR=/nix/store/…-bitcoind-inquisition  # the built package (has bin/)
EXEEXT=
[components]
ENABLE_WALLET=true
ENABLE_CLI=true
ENABLE_BITCOIND=true
```

Then run a single test standalone:

```
$ python3 <src>/test/functional/feature_templatehash.py \
    --configfile=<config.ini> --tmpdir=<tmp> --cachedir=<cache>
… Activating templatehash
… Testing basic committed OP_TEMPLATEHASH spend
… Basic testing of mutations of OP_TEMPLATEHASH spend
… Tests successful

$ python3 <src>/test/functional/feature_taproot.py --configfile=<config.ini> …
… CSFS, IK and TEMPLATEHASH Pre-activation tests...
… Activating CSFS, IK and TEMPLATEHASH
… Post-activation tests...
… Tests successful
```

**Result:** both pass. `feature_taproot.py` explicitly exercises `CSFS` (BIP348),
`INTERNALKEY` (BIP349), and `TEMPLATEHASH` (BIP446), pre- and post-activation. So the built
node *enforces* all of them. (These run on regtest, which uses the same consensus code the
node applies to signet; the opcodes are not gated per-chain.)

## 3. Are they *active on the live public signet*?

Point the node at the real signet and let it sync, then ask it:

```
$ bitcoind -signet -datadir=<dd> -txindex -addnode=inquisition.bitcoin-signet.net
# … full IBD to the tip …
$ bitcoin-cli -signet -datadir=<dd> getblockcount
315083
$ bitcoin-cli -signet -datadir=<dd> getdeploymentinfo \
    | jq -r '.deployments | to_entries[] | "\(.key): \(.value.heretical.status // .value.bip9.status)"'
anyprevout:          active
checktemplateverify: active
checksigfromstack:   active
internalkey:         active
templatehash:        active
```

**Result (at height 315,083):** all five are **`active`** on the live public signet, *right
now*. Both routes to LN-Symmetry are therefore consensus-ready on signet:

- **APO route** — `anyprevout` active.
- **CSFS route** — `checksigfromstack` + `templatehash` + `internalkey` active.

## 4. The methodological lesson

Earlier in this investigation, a project README stated the bundle would be usable on signet
"with the upcoming release of Bitcoin Inquisition" — implying *not yet*. That was
**stale/forward-looking**. The node says the opposite, and the node is ground truth. Two
separate wrong conclusions in this thread both came from trusting docs; both were corrected by
**reading the consensus code and running the node**. When these docs assert a fact, it was
checked that way.

## Reproducing

Everything here uses only this repo's `bitcoind-inquisition` package plus a synthesized
`config.ini`. The signet datadir (synced to 315,083) was kept under the working scratch dir
for reuse by the LN-Symmetry demo; a fresh sync from the tip takes ~20–30 min on a normal
connection (signet blocks are small).
