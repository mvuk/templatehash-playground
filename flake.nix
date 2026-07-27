{
  description = "templatehash-playground — a one-command, reproducible playground for the BIP448 bundle (Taproot-native rebindable transactions); first demo: Ark covenants via OP_TEMPLATEHASH (BIP446) on the public signet";

  # Reuse bark's binary cache so deps don't recompile once phase-2 CI publishes ours.
  nixConfig = {
    extra-substituters = [ "https://bark.cachix.org" ];
    extra-trusted-public-keys = [ "bark.cachix.org-1:Iaihe4ABbOQz1CHBoYUZS/sHVAcISasJZ+lL3I4gRB0=" ];
  };

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # bark, pinned to the templatehash branch. flake = false: we consume it as a source tree.
    bark = {
      url = "git+https://gitlab.com/ark-bitcoin/bark.git?ref=templatehash";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, fenix, bark }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
        lib = pkgs.lib;

        # Toolchain pin copied verbatim from bark's own flake.nix.
        rustVersion = "1.90.0";
        rustToolchain = fenix.packages.${system}.fromToolchainName {
          name = rustVersion;
          sha256 = "sha256-SJwZ8g0zF2WrKDVmHrVG3pD2RGoQeo24MEXnNx5FyuI=";
        };
        rustPlatform = pkgs.makeRustPlatform {
          cargo = rustToolchain.cargo;
          rustc = rustToolchain.rustc;
        };

        # The bark client binary (`bark`). Self-contained: bundled sqlite + webpki TLS roots.
        bark-cli = rustPlatform.buildRustPackage {
          pname = "bark-cli";
          version = "0.4.0-templatehash";
          src = bark;

          cargoLock.lockFile = "${bark}/Cargo.lock"; # 0 git deps -> no outputHashes needed

          # Build only the client bin, self-contained.
          cargoBuildFlags = [ "--package" "bark-cli" "--bin" "bark" ];
          buildNoDefaultFeatures = true;
          buildFeatures = [ "sqlite-bundled" "tls-webpki-roots" ];

          nativeBuildInputs = [
            pkgs.pkg-config
            pkgs.protobuf
            pkgs.llvmPackages.clang
          ];
          buildInputs = [ pkgs.openssl pkgs.sqlite ]
            ++ lib.optionals pkgs.stdenv.isDarwin [
              pkgs.darwin.apple_sdk.frameworks.Security
              pkgs.darwin.apple_sdk.frameworks.SystemConfiguration
            ];

          LIBCLANG_PATH = "${pkgs.llvmPackages.clang-unwrapped.lib}/lib";
          PROTOC = "${pkgs.protobuf}/bin/protoc";
          # Several build.rs shell out to git (`rev-parse HEAD`, `tag --points-at HEAD`);
          # there's no git/.git in the Nix sandbox, but they honor these env vars if set.
          GIT_HASH = "29a35ca803e9a982369542f03348a1fcd4ba97a4";
          BARK_VERSION = "0.4.0-templatehash";

          doCheck = false; # integration tests need bitcoind/postgres

          meta = {
            description = "Ark (bark) client, templatehash branch, OP_TEMPLATEHASH-capable";
            mainProgram = "bark";
            license = lib.licenses.mit;
          };
        };

        # ---- product registry (auto-discovered) --------------------------------
        # Every products/<name>/product.nix that returns { description; app; }
        # becomes `nix run .#<name>`. Drop one in via PR and it appears here.
        productsDir = ./products;
        productEntries = builtins.readDir productsDir;
        productNames = builtins.filter
          (n: productEntries.${n} == "directory"
              && n != "_template"
              && builtins.pathExists (productsDir + "/${n}/product.nix"))
          (builtins.attrNames productEntries);
        products = lib.genAttrs productNames (name:
          import (productsDir + "/${name}/product.nix") { inherit pkgs lib bark-cli; });

        defaultProduct = "bark-templatehash";
        mkApp = drv: { type = "app"; program = lib.getExe drv; };

        listApp = pkgs.writeShellApplication {
          name = "list-products";
          text = ''
            echo "templatehash-playground products:"
            echo ""
          '' + lib.concatStringsSep "\n" (lib.mapAttrsToList
            (n: p: "echo '  ${n}  —  ${p.description}'") products)
            + "\n" + ''
            echo ""
            echo "Run one with:  ./playground <name>   (or)   nix run .#<name>"
          '';
        };

        # Live localhost status page (writeShellScriptBin => no shellcheck on the heredoc HTML).
        statusApp = pkgs.writeShellScriptBin "status" ''
          export PATH=${lib.makeBinPath [ bark-cli pkgs.jq pkgs.curl pkgs.python3 pkgs.coreutils ]}''${PATH:+:$PATH}
          ${builtins.readFile ./lib/status-page.sh}
        '';
      in {
        packages = { inherit bark-cli; default = bark-cli; };

        apps = (lib.mapAttrs (_: p: mkApp p.app) products) // {
          list = mkApp listApp;
          status = mkApp statusApp;
          # `./playground` (default) opens the live status page, which also ensures the wallet.
          default = mkApp statusApp;
          playground = mkApp statusApp;
        };

        devShells.default = pkgs.mkShell {
          packages = [ bark-cli pkgs.jq pkgs.curl ];
          shellHook = ''
            echo "templatehash-playground dev shell — 'bark' is on PATH."
            echo "Try:  ./playground        (runs the ${defaultProduct} demo)"
          '';
        };
      });
}
