# Product — a local block explorer for the Inquisition signet node.
#
# Deliberately light: btc-rpc-explorer is a single Node process that answers every
# query from bitcoind's RPC, reusing the `-txindex` that `nix run .#node` already
# enables. No database, no electrum server, no nginx — unlike mempool.space, which
# needs electrs/fulcrum + MariaDB + nginx and is not runnable as a plain `nix run`.
#
# Tradeoff of staying light: address lookups (balance/history for an address) need an
# electrum backend, so they are disabled here. Blocks, transactions, mempool, fees and
# the RPC browser all work.
{ pkgs, lib, ... }:
{
  order = 10; # a tool, not a chronological demo — list it after the experiments

  description = "Local block explorer (btc-rpc-explorer) against your Inquisition signet node — no DB, no electrum";

  app = pkgs.writeShellApplication {
    name = "explorer";
    runtimeInputs = [ pkgs.btc-rpc-explorer pkgs.curl pkgs.coreutils ];
    text = ''
      DATADIR="''${INQUISITION_DATADIR:-$PWD/playground-data/inquisition}"
      PORT="''${EXPLORER_PORT:-3002}"
      RPCPORT="''${INQUISITION_RPCPORT:-38332}"
      COOKIE="$DATADIR/signet/.cookie"

      echo "== templatehash playground: block explorer =="
      echo "   node datadir: $DATADIR"
      echo ""

      # The explorer is useless without the node — fail with a pointer, not a stack trace.
      if [ ! -f "$COOKIE" ]; then
        echo "✗ No RPC cookie at $COOKIE"
        echo ""
        echo "  The Inquisition node isn't running (or hasn't finished starting)."
        echo "  Start it in another terminal first:"
        echo ""
        echo "      ./playground node"
        echo ""
        exit 1
      fi

      if ! curl -s --max-time 5 --user "$(cat "$COOKIE")" \
           --data-binary '{"jsonrpc":"1.0","method":"getblockchaininfo","params":[]}' \
           -H 'content-type: text/plain;' "http://127.0.0.1:$RPCPORT/" >/dev/null; then
        echo "✗ Node RPC on 127.0.0.1:$RPCPORT isn't answering."
        echo "  Is './playground node' still running?"
        exit 1
      fi

      echo "▶ Node RPC reachable on 127.0.0.1:$RPCPORT"
      echo "▶ Explorer starting at http://localhost:$PORT"
      echo ""
      echo "  Note: address lookups are disabled (they need an electrum server)."
      echo "  Blocks, transactions, mempool, fees and the RPC browser all work."
      echo ""

      # Point the explorer at our node. PRIVACY_MODE + NO_RATES keep it fully local:
      # no price feeds, no external API calls from a playground node.
      export BTCEXP_HOST="''${EXPLORER_HOST:-127.0.0.1}"
      export BTCEXP_PORT="$PORT"
      export BTCEXP_COIN=BTC
      export BTCEXP_BITCOIND_HOST=127.0.0.1
      export BTCEXP_BITCOIND_PORT="$RPCPORT"
      export BTCEXP_BITCOIND_COOKIE="$COOKIE"
      export BTCEXP_ADDRESS_API=none
      export BTCEXP_PRIVACY_MODE=true
      export BTCEXP_NO_RATES=true
      export BTCEXP_SLOW_DEVICE_MODE=true
      export BTCEXP_NO_INMEMORY_RPC_CACHE=false

      exec btc-rpc-explorer
    '';
  };
}
