# The consensus tests — an encyclopedic tour

The Bitcoin Inquisition node ships its own **functional tests** that pin, per opcode, exactly
which spends are valid and which are rejected (and with which error). Reading — and running —
these is how we know what the node *actually* enforces. This document catalogs them.

Files (in the inquisition source, `test/functional/`):
- `feature_templatehash.py` — a focused, standalone `OP_TEMPLATEHASH` test.
- `feature_taproot.py` — the exhaustive taproot suite; contains the `OP_TEMPLATEHASH`,
  `OP_CHECKSIGFROMSTACK`, and `OP_INTERNALKEY` spenders (bundled here, not as standalone files).
- `feature_checktemplateverify.py` — the CTV test.

---

## Part 0 — the machine: how a "test" is expressed

`feature_taproot.py` is a small **testing DSL**. Everything is a **`Spender`**: a matched pair
of *(one way to spend successfully, one way to spend that must fail)* + the exact error the
failure must produce.

### The lazy, overridable context (lines 163–190)
Every ingredient of a spend — signature, sighash, witness, annex, template hash, internal key —
is a named entry in a `ctx` dict. Entries may be plain values **or callables of `ctx`**.
- `deep_eval` / `get` — recursively evaluate & cache an entry.
- `getter(name)` / `override(expr, **kw)` — return a callable that evaluates in a *modified*
  context.

The payoff: define **one** correct way to build a spend, then **override a single ingredient**
to produce a precise near-miss.

### `make_spender` / `add_spender` (540–620)
Bundles a `scriptPubKey` with a "satisfaction function." Called with `valid=True` → the good
spend; `valid=False` → the good spend **with the `failure={…}` overrides applied**. So
`failure` *is* the experiment. It supports every spend mode: taproot key/script path, segwit
v0 (P2WPKH/P2WSH), legacy (P2PKH/bare), and P2SH-wrapping.

### Mutators (636–652)
- `bitflipper(expr)` — flip one random bit
- `zero_appender(expr)` — append a `0x00` byte
- `byte_popper(expr)` — drop the last byte

### The `ERR_*` taxonomy (654–675) — the encyclopedia of rejection reasons
Each failure asserts a verbatim consensus error. Highlights:

| Constant | Message |
|---|---|
| `ERR_CLEANSTACK` | "Stack size must be exactly one after execution" |
| `ERR_EVAL_FALSE` | "Script evaluated without error but finished with a false/empty top stack element" |
| `ERR_SIG_SCHNORR` / `ERR_SIG_SIZE` | "Invalid Schnorr signature" / "…signature size" |
| `ERR_UNKNOWN_PUBKEY` | "Public key is neither compressed or uncompressed" |
| `ERR_STACK_EMPTY` | "Operation not valid with the current stack size" |
| `ERR_EQUALVERIFY` / `ERR_CHECKSIGVERIFY` | "Script failed an OP_EQUALVERIFY / OP_CHECKSIGVERIFY operation" |
| `ERR_BAD_OPCODE` / `ERR_DISABLED_OPCODE` | "Opcode missing or not understood" / "…disabled opcode" |

The harness (`TaprootTest`) then, for each Spender: funds a UTXO, asserts the valid spend is
**accepted** (mempool *and* in a block), and the failure spend is **rejected with that exact
error** (and for "nonstandard" ones, relay-rejected but consensus-valid).

---

## Part 1 — the activation lifecycle (every opcode is tested twice)

Each new opcode has **two** generators, mirroring how it wakes up on signet:

- `*_nonstandard()` — *before* activation the opcode is a repurposed **`OP_SUCCESS`**: a script
  using it is **consensus-valid but relay-nonstandard** ("discouraged"). Proves old nodes
  won't break and these scripts are held out of the mempool until activation.
- `*_active()` — *after* activation the opcode has real, enforced semantics.

`feature_taproot.py`'s `run_test` (~2125–2155) runs the nonstandard batch, walks the
**"heretical"** deployment `defined → started → active` (mining a signaling block), then runs
the active batch — the exact Inquisition activation mechanism.

---

## Part 2 — `OP_TEMPLATEHASH` (BIP446)

### `feature_templatehash.py` (216 lines) — "does it work + can't be cheated"

**① Activation ritual** (`run_test`, 197–209). Asserts `getdeploymentinfo` shows
`templatehash` go `defined` → (144 blocks) `started` → (mine a signaling block) → (288 blocks)
`active`. Proves it is a signaled soft fork, not always-on.

**② `test_basic`** (54–90). One happy path: commit a UTXO to tapscript
`[hash, OP_TEMPLATEHASH, OP_EQUAL]`, spend it with the exact pre-committed tx, broadcast +
mine. Valid committed spend is accepted.

**③ `test_mutations`** (92–188). One valid baseline, then **7 tamper attempts that must all be
rejected** (then reverted). Each proves a field is bound by the template:

| # | Mutation | Lines |
|---|---|---|
| 1 | tx `version` 2→1 | 134–140 |
| 2 | `nLockTime` +1 | 142–148 |
| 3 | input `nSequence` −1 | 150–156 |
| 4 | output amount +1 | 158–164 |
| 5 | extra output appended | 166–172 |
| 6 | annex added | 174–179 |
| 7 | extra witness item | 181–186 |

Rejections raise `mandatory-script-verify-flag-failed`.

### `feature_taproot.py` — the exhaustive coverage (~350 spenders)

`templatehash_spenders_nonstandard()` (1452): 2 pre-activation cases proving discouragement.

`templatehash_spenders_active()` (1535):
- **Structural** (1553–1556): `basic` (push one 32-byte item; the `emptystack` twin ⇒
  `CLEANSTACK`), `2stack` (⇒ `CLEANSTACK`), `32bytes` (assert size == 32; the 33-byte twin ⇒
  `EQUALVERIFY`), `doublegood` (`OP_TEMPLATEHASH OP_TEMPLATEHASH OP_EQUAL` ⇒ deterministic).
- **Hash mutations** (1558–1564): bit-flip / pop-byte / append-zero of the committed hash ⇒
  `EVAL_FALSE`.
- **Wrong-length sweep** (1567–1571): every push length `0–255` except `32` ⇒ fail. Only the
  true 32-byte digest is accepted.
- **Annex battery** (1574–1587): 32 iterations × 3 variants (annex-committed-but-absent,
  present-but-uncommitted, mismatch) ⇒ all fail. Proves the annex is part of the template.

---

## Part 3 — `OP_CHECKSIGFROMSTACK` (CSFS, BIP348)

`bip348_csfs_spenders()` (1473). Script forms like `<msg> <pubkey> OP_CHECKSIGFROMSTACK …`.
Cases:

| Case | Proves |
|---|---|
| `simple` (✓) vs sign a *different* msg (✗ `SIG_SCHNORR`) | the message is bound exactly |
| `trunc_msg` / `extend_msg` | change message length by one byte → fails |
| `simple_fail` / `empty_pk` | empty sig ⇒ pushes false and continues; **empty pubkey ⇒ error** (`UNKNOWN_PUBKEY`) |
| `unk_pubkey` (non-32-byte key) | unknown key type ⇒ unconditionally valid (forward-compat), but a sig must exist (`STACK_EMPTY`) |
| `onearg` / `twoargs` | CSFS needs **exactly 3** stack items; too few ⇒ `STACK_EMPTY` |
| `65-byte` / `63-byte` sig | a known key's sig must be **exactly 64 bytes or empty** ⇒ off-by-one fails |

`bip348_csfs_spenders_nonstandard()` (1413): pre-activation, `OP_CHECKSIGFROMSTACK` is a
discouraged `OP_SUCCESS` (script still "succeeds", but relay-nonstandard).

---

## Part 4 — `OP_INTERNALKEY` (BIP349)

`spenders_internalkey_active()` (717). Script `OP_INTERNALKEY OP_EQUAL`: the opcode pushes the
32-byte taproot internal key; the input pushes the expected key; `OP_EQUAL` compares.
- success: input is the true internal key (`pubs[0]`).
- failure: input is a different key (`pubs[1]`) ⇒ `EVAL_FALSE`.

`bip349_ik_spenders_nonstandard()` (1432): pre-activation discouragement, same shape as the
others.

---

## Part 5 — `OP_CHECKTEMPLATEVERIFY` (CTV, BIP119)

`feature_checktemplateverify.py` (738 lines, older/comprehensive). Exercises CTV in **both
segwit v0 and taproot**, builds output **trees** by depth, spends at specific positions,
checks non-32-byte / empty-stack arguments, disallows multiple inputs when specified, verifies
mempool + block acceptance, and rejects mutated spends
(`mandatory-script-verify-flag-failed (Script failed an OP_CHECKTEMPLATEVERIFY operation)`).

CTV *bakes in* the comparison; `TEMPLATEHASH` hands you the digest to compose. The
`feature_templatehash.py` script literally re-implements CTV as
`<hash> OP_TEMPLATEHASH OP_EQUAL`.

---

## What you learn

1. These are **consensus** tests — the specification made executable, per opcode.
2. The **matched valid/invalid pair + exact error** pattern is how Bitcoin proves a soft fork
   does *precisely* what's specified and nothing more.
3. The bundle's division of labor is legible in the tests: `TEMPLATEHASH` (commit to your
   spending tx), `CSFS` (verify a sig over arbitrary data), `INTERNALKEY` (name the taproot
   key), `CTV` (one-shot template check). **LN-Symmetry = TEMPLATEHASH ∘ CSFS** — sign over a
   rebindable template — and both halves are present, tested, and passing.

To see these run (they pass against this repo's node), see
[`signet-verification.md`](./signet-verification.md).
