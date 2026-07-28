# Project #1 — LN-Symmetry (eltoo) on Core Lightning.
# instagibbs' CLN eltoo fork (branch 2026-01-eltoo_templatehash), built reproducibly.
# eltoo needs rebindable signatures (ANYPREVOUT, or CSFS+TEMPLATEHASH) — all live on signet.
{ pkgs, lib, clightning-eltoo, ... }:
{
  order = 1; # eltoo (2018) predates templatehash (2025) — first by lineage
  description = "LN-Symmetry (eltoo) Core Lightning node — APO/TEMPLATEHASH channels, no penalty txs";

  app = pkgs.writeShellApplication {
    name = "ln-symmetry";
    runtimeInputs = [ clightning-eltoo pkgs.coreutils ];
    text = ''
      echo "== LN-Symmetry (eltoo) — project #1 =="
      echo "instagibbs' Core Lightning eltoo fork, built reproducibly with Nix."
      echo ""
      echo "> node version:"
      lightningd --version
      echo ""
      echo "> eltoo subdaemons (regular Lightning has none of these):"
      for f in ${clightning-eltoo}/libexec/c-lightning/*eltoo*; do
        echo "   - $(basename "$f")"
      done
      echo ""
      echo "eltoo replaces Lightning's penalty transactions with a symmetric"
      echo "'latest-state-wins' ratchet: APO-rebindable update + settle transactions."
      echo "The opcodes it needs (ANYPREVOUT / CSFS / TEMPLATEHASH) are live on the"
      echo "public signet — see docs/signet-verification.md."
      echo ""
      echo "Drive a live eltoo node against the inquisition signet:"
      echo "  1) nix run .#node        # start a synced inquisition signet bitcoind"
      echo "  2) lightningd --network=signet --lightning-dir=./playground-data/ln \\"
      echo "       --bitcoin-datadir=./playground-data/inquisition \\"
      echo "       --bitcoin-rpcconnect=127.0.0.1 --bitcoin-rpcport=38332 --developer"
      echo "  3) lightning-cli --network=signet --lightning-dir=./playground-data/ln getinfo"
      echo ""
      echo "Full runbook + eltoo mechanics: docs/ln-symmetry-eltoo.md"
    '';
  };
}
