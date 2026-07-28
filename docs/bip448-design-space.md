# The BIP448 design space — what the bundle *generatively* unlocks

Eltoo and Ark are just two consumers. This document is about the **general** expansion of
Bitcoin's expressiveness the bundle creates — the new *primitives*, and the space of things
they compose into, independent of any particular L2.

## The core idea: three new questions an output can ask

Historically a Bitcoin output (script) can essentially only ask:

> *"Is there a valid signature for this key, and are the timelocks satisfied?"*

It is almost **blind** — blind to the transaction spending it, and blind to any data outside
that transaction. The bundle adds **three orthogonal new questions**:

1. **"Does the spending transaction have *this shape*?"**
   — `OP_TEMPLATEHASH` (push the spending-tx digest) / `OP_CHECKTEMPLATEVERIFY` (assert it).
   This is **transaction introspection** → *covenants*: an output can constrain *how* it is
   spent (which outputs, amounts, structure).

2. **"Is there a valid signature over *this arbitrary data*?"**
   — `OP_CHECKSIGFROMSTACK`. Signature checking is **decoupled from the transaction**: verify a
   signature over *any* message on the stack. This turns script into a general **verifier of
   external attestations**.

3. **"Can a pre-signed transaction attach to *any matching output*?"**
   — `SIGHASH_ANYPREVOUT` (directly), or `TEMPLATEHASH`+`CSFS` (emulated). **Rebindable /
   floating transactions**: a signature that isn't nailed to one specific prevout.

Plus a small piece of **composability glue**:

4. `OP_INTERNALKEY` — a script can reference "the taproot key behind *this* output" on the
   stack, so the above can be wired together without hardcoding keys.

The bip448 project frames these as: *rebindable transactions*, *next-transaction commitment*,
and *signature verification of arbitrary messages*. Those are the axes of the design space.

## Why this is *generative* (composition, not a fixed feature list)

The power isn't the individual opcodes; it's that they **compose multiplicatively**:

```
   introspection   ×   arbitrary-data verification   ×   rebinding
  (TEMPLATEHASH/CTV)         (CSFS)                    (APO / TH+CSFS)
```

- introspection alone → **covenants** (constrain the next tx).
- introspection × rebinding → **eltoo** (a floating tx that can re-attach to newer state).
- introspection × data-verification → **covenants gated by external facts** (an output whose
  spend path depends on an oracle's signature).
- data-verification alone → **on-chain checks of off-chain agreements** (delegation, oracles).

Each new primitive doesn't add one feature — it multiplies the reachable protocol space.

## A catalog of L2-agnostic applications

None of these are "an L2"; they're general capabilities the bundle enables.

### Covenant applications (introspection)
- **Vaults** — force coins through a delay with a designated recovery path. If keys are
  stolen, the covenant forces a timelock window during which funds can be clawed back to cold
  storage. A canonical CTV/TEMPLATEHASH use.
- **Congestion-control / batch payouts** — commit on-chain to a *tree* of future payouts in
  one output; recipients unroll their branch later. An exchange can settle thousands of
  withdrawals into one output during high fees and let users expand lazily.
- **Timeout trees** — trees of outputs/HTLCs that expire, enabling scalable shared-UTXO
  constructs without per-user interaction.
- **Coinpools / payment pools / joinpools** — a single UTXO shared by N parties with
  covenant-enforced exit paths; parties can leave (or the pool can rebalance) without full
  N-of-N cooperation for every move.
- **Non-interactive / one-shot constructions** — because a covenant can pre-commit structure,
  many setups that used to need multi-party signing rounds become one-sided.

### Oracle & agreement applications (arbitrary-data verification)
- **Discreet Log Contracts (DLCs), simplified** — today a DLC pre-signs a Contract Execution
  Transaction (and adaptor signature) for *every* possible oracle outcome. With **CSFS**, the
  script can verify the oracle's signature over the outcome *directly*, collapsing that
  combinatorial setup. This is one of the biggest non-L2 wins: prediction markets, insurance,
  parametric contracts, hedging — all get dramatically simpler.
- **Delegation / spending policies** — a key can sign a *delegation message* ("key B may spend
  under conditions C"); the script verifies that delegation sig via CSFS plus B's signature.
  Authority can be granted/rotated without moving coins.
- **Proof-carrying spends** — require a signature over an assertion (a commitment, a policy
  amendment, an off-chain state) as a spend condition.

### Rebinding / floating-transaction applications
- **eltoo / LN-Symmetry** — the flagship, but the primitive is general: any protocol wanting a
  pre-signed transaction that isn't pinned to a specific prevout.
- **Fee & sponsorship constructs** — floating transactions that can be attached where needed at
  broadcast time.

### Bigger-picture constructions
- **Spacechains / commitment chains** — CTV-style covenants can commit to chains of future
  transactions, enabling sidechain-like constructions without new trust assumptions.
- **UTXO sharing at scale** — the common thread behind Ark, timeout trees, and payment pools:
  many users share one on-chain footprint, with covenants enforcing safe exit.

## The deliberate *limits* (why this design, not OP_CAT/MATT)

Importantly, BIP448 is **not** a general-purpose recursion/programmability engine:

- Plain CTV/TEMPLATEHASH is **not recursive** — the committed template is a fixed hash, so an
  output can constrain its *child* but not enforce an arbitrarily-deep *lineage* by itself.
- The bundle is a **bounded, "simple and well-understood"** set, chosen to maximize useful
  capability while minimizing unintended-consequence surface — explicitly contrasted with
  fully general approaches (`OP_CAT`, MATT/`OP_CHECKCONTRACTVERIFY`) that unlock more but carry
  larger analysis burden.

That "expandable but bounded" character is the point: it opens a large, *analyzable* design
space — covenants, oracles, delegation, rebinding — rather than an open-ended one.

## The one-sentence version

> The bundle lets a coin, for the first time, condition its spend on **the shape of the
> spending transaction**, on **a signature over arbitrary external data**, and on **being
> re-attachable to any matching output** — three orthogonal powers that *multiply* into
> vaults, congestion control, DLCs/oracles, delegation, payment pools, and rebindable
> protocols like eltoo — without opening the door to unbounded recursion.
