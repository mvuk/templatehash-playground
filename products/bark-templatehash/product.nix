# Product #1 — the reference example.
# An Ark (bark) wallet on the public signet, pointed at the OP_TEMPLATEHASH
# covenant ASP (ark.templatehash.com) instead of bark's default signet ASP.
{ pkgs, lib, bark-cli }:
{
  description = "Ark covenant wallet on signet via OP_TEMPLATEHASH (BIP446), ASP = ark.templatehash.com";

  app = pkgs.writeShellApplication {
    name = "bark-templatehash";
    runtimeInputs = [ bark-cli pkgs.jq ];
    text = ''
      # NOTE: bark's --signet default ASP is ark.signet.2nd.dev (the MAIN signet ark).
      # templatehash requires overriding it. esplora defaults to the shared signet source.
      ARK="''${TEMPLATEHASH_ARK:-ark.templatehash.com}"
      DATADIR="''${BARK_DATADIR:-$PWD/playground-data/bark-templatehash}"
      export BARK_DATADIR="$DATADIR"
      mkdir -p "$(dirname "$DATADIR")"

      echo "== templatehash playground: bark + OP_TEMPLATEHASH =="
      echo "   datadir: $DATADIR"
      echo "   ASP:     $ARK"
      echo ""

      if [ ! -e "$DATADIR/db.sqlite" ]; then
        echo "▶ Creating a covenant-enabled signet wallet…"
        bark create --signet --datadir "$DATADIR" --ark "$ARK"
      else
        echo "▶ Reusing existing wallet."
      fi

      echo ""
      echo "▶ Ark server (OP_TEMPLATEHASH ASP):"
      bark -q ark-info | jq '{network, server_pubkey, round_interval, min_board_amount_sat}'

      VTXO="$(bark -q address)"
      ONCHAIN="$(bark -q onchain address | jq -r .address)"
      echo ""
      echo "▶ Your addresses:"
      echo "   VTXO (Ark):  $VTXO"
      echo "   on-chain:    $ONCHAIN"
      echo ""
      echo "▶ Balance:"
      bark -q balance | jq

      echo ""
      echo "Fund it (manual until phase 2 wires the faucet API) at https://signet.2nd.dev :"
      echo "  • send signet coins to the on-chain address above, then board into Ark:"
      echo "        bark board --all      (min board amount is shown in ark-info above)"
      echo "  • or request an Ark VTXO straight to the VTXO address above"
      echo ""
      echo "Then explore:  bark balance | vtxos | send | history   (see: bark --help)"
    '';
  };
}
