{
  description = "templatehash-playground — a one-command, reproducible playground for the BIP448 bundle (Taproot-native rebindable transactions); first demo: Ark covenants via OP_TEMPLATEHASH (BIP446) on the public signet";

  # Reuse bark's binary cache so deps don't recompile once phase-2 CI publishes ours.
  nixConfig = {
    extra-substituters = [
      "https://templatehash-playground.cachix.org"
      "https://bark.cachix.org"
    ];
    extra-trusted-public-keys = [
      "templatehash-playground.cachix.org-1:NzG5hoXN6gRR27AtwG1bmK4lMxYftVAy5+4ZLIBVI2Y="
      "bark.cachix.org-1:Iaihe4ABbOQz1CHBoYUZS/sHVAcISasJZ+lL3I4gRB0="
    ];
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
    # (E) Bitcoin Inquisition is a fork of Core 29.x, so we base its derivation on a
    # nixpkgs pin where bitcoind is 29.x (mirrors how nix-bitcoin vendors bitcoind_29).
    nixpkgs-bitcoind29.url = "github:NixOS/nixpkgs/nixos-25.05";
    inquisition = {
      url = "github:bitcoin-inquisition/bitcoin?ref=29.x";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, fenix, bark, nixpkgs-bitcoind29, inquisition }:
    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
        lib = pkgs.lib;

        # (E) bitcoin-inquisition: a fork of Core 29.x that enables the BIP446/448 opcodes
        # on the ordinary global signet. Based on a nixpkgs pin whose bitcoind is 29.x.
        pkgs29 = import nixpkgs-bitcoind29 { inherit system; };
        bitcoind-inquisition = pkgs29.bitcoind.overrideAttrs (_: {
          pname = "bitcoind-inquisition";
          version = "29.x-inquisition";
          src = inquisition;
          doInstallCheck = false; # upstream versionCheckHook won't match the fork's version string
        });

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

        # Entry dispatcher baked into the Docker image so `docker run <image> <product>` works.
        dockerEntry = pkgs.writeShellScriptBin "playground-entry" ''
          export PATH=${lib.makeBinPath [ bark-cli pkgs.jq pkgs.curl pkgs.python3 pkgs.coreutils ]}:$PATH
          export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
          cmd="''${1:-default}"; [ $# -gt 0 ] && shift || true
          case "$cmd" in
            ""|default|status|playground) exec ${statusApp}/bin/status "$@" ;;
            bark-templatehash)             exec ${products.bark-templatehash.app}/bin/bark-templatehash "$@" ;;
            bark)                          exec bark "$@" ;;
            list)                          exec ${listApp}/bin/list-products ;;
            *) echo "unknown product: $cmd (try: default | bark-templatehash | bark | list)"; exit 2 ;;
          esac
        '';

        # Prebuilt OCI image (Linux only): `docker run -p 4848:4848 ghcr.io/mvuk/templatehash-playground`.
        dockerImage = pkgs.dockerTools.buildLayeredImage {
          name = "templatehash-playground";
          tag = "latest";
          config = {
            Entrypoint = [ "${dockerEntry}/bin/playground-entry" ];
            ExposedPorts = { "4848/tcp" = { }; };
            Env = [ "PLAYGROUND_PORT=4848" ];
            WorkingDir = "/tmp";
          };
        };

        # (E) Run a local Bitcoin Inquisition node on the global signet.
        nodeApp = pkgs.writeShellScriptBin "node" ''
          export PATH=${lib.makeBinPath [ bitcoind-inquisition pkgs.coreutils ]}:$PATH
          DATADIR="''${INQUISITION_DATADIR:-$PWD/playground-data/inquisition}"
          mkdir -p "$DATADIR"
          echo "Starting bitcoin-inquisition on the (global) signet — datadir: $DATADIR"
          echo "Same signet everyone uses, but this node enforces the BIP446/448 opcodes."
          exec bitcoind -signet -datadir="$DATADIR" -txindex -server "$@"
        '';
      in {
        packages = { inherit bark-cli; default = bark-cli; }
          // lib.optionalAttrs pkgs.stdenv.isLinux {
            inherit bitcoind-inquisition;
            docker = dockerImage;
          };

        apps = (lib.mapAttrs (_: p: mkApp p.app) products) // {
          list = mkApp listApp;
          status = mkApp statusApp;
          # `./playground` (default) opens the live status page, which also ensures the wallet.
          default = mkApp statusApp;
          playground = mkApp statusApp;
        } // lib.optionalAttrs pkgs.stdenv.isLinux {
          node = mkApp nodeApp; # (E) local inquisition signet node (Linux)
        };

        devShells.default = pkgs.mkShell {
          packages = [ bark-cli pkgs.jq pkgs.curl ];
          shellHook = ''
            echo "templatehash-playground dev shell — 'bark' is on PATH."
            echo "Try:  ./playground        (runs the ${defaultProduct} demo)"
          '';
        };

        # `nix flake check` runs these (plus builds every package/devShell for the system).
        checks.bootstrap-shellcheck = pkgs.runCommand "bootstrap-shellcheck"
          { nativeBuildInputs = [ pkgs.shellcheck ]; }
          "shellcheck -S warning ${./playground}; touch $out";

        formatter = pkgs.nixfmt-rfc-style;
      }))
    // {
      # (E) The nix-bitcoin-mergeable artifact: a NixOS module for a Bitcoin Inquisition
      # signet node. System-agnostic; builds its own 29.x-based package by default.
      nixosModules.inquisition-node =
        import ./modules/inquisition-node.nix { inherit inquisition nixpkgs-bitcoind29; };
    };
}
