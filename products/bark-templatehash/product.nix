# Product #1 — the reference example.
# An Ark (bark) wallet on the public signet, pointed at the OP_TEMPLATEHASH
# covenant ASP (ark.templatehash.com) rather than bark's default signet ASP.
{ pkgs, lib, bark-cli }:
{
  description = "Ark covenant wallet on signet via OP_TEMPLATEHASH (BIP446), ASP = ark.templatehash.com";

  app = pkgs.writeShellApplication {
    name = "bark-templatehash";
    runtimeInputs = [ bark-cli pkgs.jq pkgs.curl ];
    text = ''
      set -euo pipefail

      # IMPORTANT: bark's --signet default ASP is ark.signet.2nd.dev (the MAIN
      # signet ark). templatehash requires overriding it explicitly.
      ARK="''${TEMPLATEHASH_ARK:-ark.templatehash.com}"
      DATADIR="''${BARK_DATADIR:-$PWD/playground-data/bark-templatehash}"
      FAUCET="https://signet.2nd.dev"

      echo "== templatehash playground: bark + OP_TEMPLATEHASH =="
      echo "   datadir: $DATADIR"
      echo "   ASP:     $ARK   (esplora defaults to the shared signet source)"
      echo ""

      if [ ! -e "$DATADIR" ]; then
        echo "▶ Creating a covenant-enabled signet wallet…"
        bark create --signet --datadir "$DATADIR" --ark "$ARK"
      else
        echo "▶ Reusing existing wallet at $DATADIR"
      fi

      echo ""
      echo "▶ Wallet info:"
      bark --datadir "$DATADIR" ark-info || true

      echo ""
      echo "Next steps (funding is a manual step until phase 2 wires the faucet API):"
      echo "  1. Get a receive address:   bark --datadir $DATADIR onchain address"
      echo "  2. Fund it at:              $FAUCET   (on-chain or Ark VTXO)"
      echo "  3. Check balance:           bark --datadir $DATADIR balance"
      echo ""
      echo "(Exact subcommands are verified against 'bark --help' during the build pass.)"
    '';
  };
}
