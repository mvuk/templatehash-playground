# Product template — copy this directory to products/<your-experiment>/ and edit.
# Anything you return here as `app` becomes `nix run .#<your-experiment>`.
# Open a PR and it shows up in the playground automatically.
#
# You receive:
#   pkgs      - nixpkgs for the current system
#   lib       - nixpkgs lib
#   bark-cli  - the built `bark` binary (mainProgram = "bark")
{ pkgs, lib, bark-cli }:
{
  description = "One line describing what this experiment demonstrates";

  app = pkgs.writeShellApplication {
    name = "my-experiment";
    runtimeInputs = [ bark-cli pkgs.jq pkgs.curl ];
    text = ''
      set -euo pipefail
      echo "Hello from my templatehash experiment!"
      # bark --datadir ./playground-data/my-experiment create --signet --ark ark.templatehash.com
    '';
  };
}
