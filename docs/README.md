# templatehash-playground — deep-dive docs

These documents record, in detail, the covenant/soft-fork machinery this playground sits
on, and the **empirical** work we did to verify it against a real node (not READMEs).

Everything here was derived by reading and **running** the Bitcoin Inquisition node
(`bitcoind-inquisition v29.4.0`, a fork of Bitcoin Core 29.x) that this repo packages, and
by syncing it to the **live public signet**.

## The one-line headline

> On the live public signet (verified at block height **315,083** with our own node's
> `getdeploymentinfo`), **all five bundle opcodes are `active`**:
> `anyprevout`, `checktemplateverify`, `checksigfromstack`, `internalkey`, `templatehash`.

That means the consensus layer for both **Ark covenants** (via `OP_TEMPLATEHASH`) and
**LN-Symmetry / eltoo** (via `SIGHASH_ANYPREVOUT`, or `CSFS`+`TEMPLATEHASH`) is *live today*.

## Contents

1. [**The BIP448 bundle**](./bip448-bundle.md) — what each opcode is, what it does, and how
   they compose. `CTV`, `TEMPLATEHASH`, `CSFS`, `INTERNALKEY`, `ANYPREVOUT`.
2. [**The consensus tests**](./opcode-consensus-tests.md) — an encyclopedic tour of the
   node's own functional tests (the "spender" DSL, every `OP_TEMPLATEHASH`/`CSFS`/`IK` case,
   and the activation lifecycle).
3. [**Signet verification**](./signet-verification.md) — how we *empirically* proved the
   node enforces these opcodes (ran its tests) and that they're *active on signet* (synced +
   `getdeploymentinfo`). Includes the exact commands.
4. [**LN-Symmetry / eltoo**](./ln-symmetry-eltoo.md) — how eltoo actually works (rebinding,
   the update+settle ratchet, ephemeral anchors), the Core Lightning implementation we're
   building, and the demo runbook. This is the basis for **project #2** of the playground.

## A note on method

Twice during this investigation, a confident conclusion drawn from project READMEs turned
out to be wrong (a doc said the bundle was "upcoming" on signet; it was actually live). The
correction each time came from **the node itself** — reading its consensus code and running
its tests. Where these docs state something as fact, it was checked against the node.
