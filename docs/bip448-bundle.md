# The BIP448 bundle — the opcodes, and how they compose

**BIP448** ("Taproot-native (re)bindable transactions") is not a single opcode — it's a
*bundle* of small, tapscript-only primitives that together unlock covenants and eltoo-style
Lightning. It draws on the earlier **LNHANCE** (CTV + CSFS + INTERNALKEY) and **CTV+CSFS**
lines of work. The Bitcoin Inquisition signet has these active so they can be exercised for
real before any mainnet activation.

This playground's node (`bitcoind-inquisition v29.4.0`) implements and enforces all of them.

## The problem they solve

Two long-standing wishes in Bitcoin scripting:

1. **Covenants** — let an output restrict *how* it may be spent (e.g. "only into this exact
   set of outputs"). Enables vaults, congestion control, and Ark-style shared UTXOs.
2. **Rebindable signatures** — let a pre-signed transaction spend *any* output that matches a
   shape, not one specific outpoint. This is what **eltoo / LN-Symmetry** needs to replace
   Lightning's penalty mechanism.

## The five opcodes / sighashes

| Name | BIP | Kind | One-liner |
|---|---|---|---|
| `OP_CHECKTEMPLATEVERIFY` (CTV) | 119 | verify | fail unless the spending tx matches a committed template hash |
| `OP_TEMPLATEHASH` | 446 | push | push the hash of the spending tx's "template" onto the stack |
| `OP_CHECKSIGFROMSTACK` (CSFS) | 348 | verify | verify a signature over an **arbitrary message** taken from the stack |
| `OP_INTERNALKEY` | 349 | push | push the taproot **internal key** of the output being spent |
| `SIGHASH_ANYPREVOUT` (APO) | 118 | sighash flag | a signature that does **not** commit to which prevout it spends |

### `OP_CHECKTEMPLATEVERIFY` (CTV, BIP119) — the one-shot covenant
Form: `<32-byte template hash> OP_CHECKTEMPLATEVERIFY`. The opcode computes the "template
hash" of the *current* spending transaction (its version, locktime, inputs count, sequences,
outputs, input index…) and **fails** unless it equals the hash on the stack. It does not pop
the hash. Works in both segwit v0 and taproot. This is the simplest covenant: "this coin can
only ever be spent by a transaction that looks *exactly* like X."

### `OP_TEMPLATEHASH` (BIP446) — the composable covenant
Form: `OP_TEMPLATEHASH`. Instead of *verifying*, it **computes the same kind of template
hash and pushes it onto the stack**. You then decide what to do with it:
- `OP_TEMPLATEHASH OP_EQUAL` against a committed value ⇒ you've re-implemented CTV; or
- feed the pushed hash into **`OP_CHECKSIGFROMSTACK`** ⇒ you can require a *signature over
  the template*, which is the ingredient for rebindable constructions.

BIP446's hash is **taproot-native** and **commits to the taproot annex** (BIP119's does not).
So they are related but not byte-identical, and TEMPLATEHASH is strictly more flexible
because the digest becomes a first-class stack item.

### `OP_CHECKSIGFROMSTACK` (CSFS, BIP348) — verify a signature over *data*
Form: `<message> <pubkey> OP_CHECKSIGFROMSTACK` with the signature supplied on the witness
stack. Pushes `1` iff the BIP340 Schnorr signature is valid for `pubkey` over `message` — and
crucially `message` is **arbitrary data from the stack, not the transaction**. Rules the tests
pin: message is bound exactly (one byte's difference fails); a known key's signature must be
exactly 64 bytes or empty; an empty signature pushes false but an empty pubkey is an error;
unknown (non-32-byte) key types are treated as unconditionally-valid for forward compatibility.

**Why it matters:** "verify a signature over data I hand you" + `OP_TEMPLATEHASH` (which hands
you the digest of *another* transaction's template) = you can check a signature over a
*different* transaction ⇒ **rebinding without APO**.

### `OP_INTERNALKEY` (BIP349) — name the taproot key
Form: `OP_INTERNALKEY` pushes the 32-byte x-only **internal key** the taproot output was
constructed from (the key in the control block). Lets a tapscript reference "the key behind
this very output" without hardcoding it — composability glue for the above.

### `SIGHASH_ANYPREVOUT` (APO, BIP118) — the rebindable sighash
Not an opcode but a **signature hash flag**. A normal signature commits to the exact input
(`prevout`) being spent; APO **omits the prevout** from the sighash preimage. So the same
signature validates against *any* output whose amount and script match. This is the direct,
original route to eltoo/LN-Symmetry (the CSFS+TEMPLATEHASH route emulates it).

## How they compose

- **Ark / templatehash.com** uses `OP_TEMPLATEHASH` for covenants over shared UTXO (VTXO)
  trees — the basis of **project #1** (`bark-templatehash`).
- **LN-Symmetry / eltoo** needs *rebinding*. Two ways, both live on signet:
  - **APO route** — sign channel update txs with `SIGHASH_ANYPREVOUT` so a newer state can
    spend an older state's output. (instagibbs' original eltoo.)
  - **CSFS route** — `OP_TEMPLATEHASH` produces the next-state template digest, `CSFS` checks
    a signature over it. (The BIP448 way; also what the `2026-01-eltoo_templatehash` CLN
    branch migrates toward.)

See [`ln-symmetry-eltoo.md`](./ln-symmetry-eltoo.md) for the eltoo mechanics, and
[`opcode-consensus-tests.md`](./opcode-consensus-tests.md) for exactly how the node tests each
of these.
