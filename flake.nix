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
    # (project #1: ln-symmetry) the eltoo Core Lightning fork is based on clightning 26.04,
    # which lives in this nixpkgs pin (nixos-25.11 ships an older clightning).
    nixpkgs-cln.url = "github:NixOS/nixpkgs/624af665418d3c65d544145b4d34ad696439570e";
  };

  outputs = { self, nixpkgs, flake-utils, fenix, bark, nixpkgs-bitcoind29, inquisition, nixpkgs-cln }:
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

        # (project #1: ln-symmetry) instagibbs' Core Lightning eltoo fork, branch
        # 2026-01-eltoo_templatehash. Based on clightning 26.04 (nixpkgs-cln). Ships a full
        # eltoo channel state machine; we build+install the two eltoo subdaemons the branch's
        # install list forgot, and run its eltoo settle-tx unit test in the build.
        pkgsCln = import nixpkgs-cln { inherit system; };
        clightning-eltoo = pkgsCln.clightning.overrideAttrs (old: {
          pname = "clightning-eltoo";
          version = "eltoo-templatehash";
          src = pkgsCln.fetchFromGitHub {
            owner = "instagibbs";
            repo = "lightning";
            rev = "c7710830769646fe7a6b1e45bd191333cbf62d6c";
            fetchSubmodules = true;
            hash = "sha256-Z5ZdIxVUr9wJLJsDiG4iAtStcp83cROz8pr/6Ygq5FM=";
          };
          makeFlags = [ "VERSION=v26.04.1-eltoo" ];
          doInstallCheck = false;
          # Run the eltoo settle-tx C unit test in the build (exercises the APO rebinding logic).
          doCheck = true;
          checkPhase = ''
            runHook preCheck
            echo "=== building eltoo settle-tx unit test ==="
            make VERSION=v26.04.1-eltoo -j''${NIX_BUILD_CORES:-2} channeld/test/run-settle_tx
            echo "=== running eltoo settle-tx unit test ==="
            ./channeld/test/run-settle_tx
            echo "=== eltoo settle-tx unit test PASSED ==="
            runHook postCheck
          '';
          # The branch builds lightning_eltoo_{channeld,onchaind} (in ALL_PROGRAMS) but forgot
          # them in PKGLIBEXEC_PROGRAMS, so `make install` skips them. Build + install by hand.
          postInstall = (old.postInstall or "") + ''
            echo "Building + installing the missing eltoo subdaemons…"
            make VERSION=v26.04.1-eltoo -j''${NIX_BUILD_CORES:-2} \
              lightningd/lightning_eltoo_channeld lightningd/lightning_eltoo_onchaind
            install -m0755 -t "$out/libexec/c-lightning" \
              lightningd/lightning_eltoo_channeld lightningd/lightning_eltoo_onchaind
            # expose the eltoo settle-tx unit test binary (built in checkPhase) for the UI's test button
            install -Dm0755 channeld/test/run-settle_tx "$out/libexec/eltoo-tests/run-settle_tx"
          '';
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
          # Modern nixpkgs darwin stdenv provides the SDK frameworks automatically;
          # with tls-webpki-roots + sqlite-bundled we don't need to add any.
          buildInputs = [ pkgs.openssl pkgs.sqlite ];

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
          import (productsDir + "/${name}/product.nix") { inherit pkgs lib bark-cli clightning-eltoo; });
        # Order by each project's `order` field (chronological: ln-symmetry/eltoo #1, templatehash #2).
        orderedProductNames = lib.sort
          (a: b: (products.${a}.order or 99) < (products.${b}.order or 99)) productNames;

        defaultProduct = "bark-templatehash";
        # ln-symmetry needs the CLN eltoo build, so it's Linux-only; bark builds everywhere.
        appProducts = if pkgs.stdenv.isLinux then products
                      else builtins.removeAttrs products [ "ln-symmetry" ];
        mkApp = drv: { type = "app"; program = lib.getExe drv; };

        listApp = pkgs.writeShellApplication {
          name = "list-products";
          text = ''
            echo "templatehash-playground products:"
            echo ""
          '' + lib.concatStringsSep "\n" (map
            (n: "echo '  ${n}  —  ${products.${n}.description}'") orderedProductNames)
            + "\n" + ''
            echo ""
            echo "Run one with:  ./playground <name>   (or)   nix run .#<name>"
          '';
        };

        # Live localhost control panel: serves the prebuilt shadcn UI (./ui/dist), computes
        # status.json, and exposes the toggle/test API (lib/server.py). eltoo/node bits are
        # Linux-only; on macOS the eltoo toggle + bundle tests report "not available".
        statusApp = pkgs.writeShellScriptBin "status" (''
          export PATH=${lib.makeBinPath ([ bark-cli pkgs.jq pkgs.curl pkgs.python3 pkgs.coreutils pkgs.procps ]
            ++ lib.optionals pkgs.stdenv.isLinux [ bitcoind-inquisition clightning-eltoo ])}''${PATH:+:$PATH}
          export PLAYGROUND_UI="${./ui/dist}"
          export INQ_SRC="${inquisition}"
          export BARK_DATADIR="''${BARK_DATADIR:-$PWD/playground-data/bark-templatehash}"
        '' + lib.optionalString pkgs.stdenv.isLinux ''
          export RUN_SETTLE_TX="${clightning-eltoo}/libexec/eltoo-tests/run-settle_tx"
          export INQ_PKG="${bitcoind-inquisition}"
        '' + ''
          if [ ! -e "$BARK_DATADIR/db.sqlite" ]; then
            bark create --signet --datadir "$BARK_DATADIR" --ark ark.templatehash.com || true
          fi
          chmod 600 "$BARK_DATADIR/db.sqlite" 2>/dev/null || true
          exec python3 ${./lib/server.py}
        '');

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
            Env = [ "PLAYGROUND_PORT=4848" "PLAYGROUND_HOST=0.0.0.0" ];
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
            inherit bitcoind-inquisition clightning-eltoo;
            docker = dockerImage;
          };

        apps = (lib.mapAttrs (_: p: mkApp p.app) appProducts) // {
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
