# NixOS module for a Bitcoin Inquisition signet node.
#
# This is the nix-bitcoin-mergeable artifact: enable it in a NixOS config to run a
# node that enforces the BIP446/448 opcodes on the ordinary global signet.
#
# Usage:
#   imports = [ inputs.templatehash-playground.nixosModules.inquisition-node ];
#   services.inquisition-node.enable = true;
{ inquisition, nixpkgs-bitcoind29 }:
{ config, lib, pkgs, ... }:
let
  cfg = config.services.inquisition-node;
  defaultPackage = (import nixpkgs-bitcoind29 { inherit (pkgs.stdenv.hostPlatform) system; }).bitcoind.overrideAttrs (_: {
    pname = "bitcoind-inquisition";
    version = "29.x-inquisition";
    src = inquisition;
    doInstallCheck = false;
  });
in
{
  options.services.inquisition-node = {
    enable = lib.mkEnableOption "Bitcoin Inquisition signet node (BIP446/448 on the global signet)";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalMD "bitcoind-inquisition (Core 29.x fork)";
      description = "The bitcoind-inquisition package to run.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/inquisition";
      description = "Node data directory.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "-prune=550";
      description = "Extra arguments appended to the bitcoind command line.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.inquisition = {
      isSystemUser = true;
      group = "inquisition";
      home = cfg.dataDir;
    };
    users.groups.inquisition = { };

    systemd.services.inquisition-node = {
      description = "Bitcoin Inquisition signet node";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        User = "inquisition";
        Group = "inquisition";
        ExecStart = "${cfg.package}/bin/bitcoind -signet -datadir=${cfg.dataDir} -txindex -server ${cfg.extraArgs}";
        Restart = "on-failure";
        RestartSec = "10s";
        StateDirectory = "inquisition";
        StateDirectoryMode = "0710";
      };
    };
  };
}
