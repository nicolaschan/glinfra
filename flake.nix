{
  description = "glinfra";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      eachSystem = f: nixpkgs.lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
      gleamDeps = pkgs: with pkgs; [ gleam erlang rebar3 ];
    in
    {
      packages = eachSystem (system: pkgs: {
        # Fixed-output derivation that downloads Hex packages.
        # After changing gleam dependencies, update the hash:
        #   nix build .#deps 2>&1 | grep 'got:'
        deps = pkgs.stdenv.mkDerivation {
          pname = "glinfra-deps";
          version = "1.0.0";
          src = self;
          nativeBuildInputs = gleamDeps pkgs;
          buildPhase = ''
            export HOME=$TMPDIR
            cd infra
            gleam deps download
          '';
          installPhase = ''
            mkdir -p $out
            cp -r build/packages/* $out/
            # Gleam skips network resolution when gleam.lock matches manifest.toml
            cp manifest.toml $out/gleam.lock
          '';
          outputHashAlgo = "sha256";
          outputHashMode = "recursive";
          outputHash = "sha256-P3mB4JB9iO0NdIsW4oj7gqxCl3Fss0k82ZyZxDLgY00=";
        };

        default = pkgs.stdenv.mkDerivation {
          pname = "infra";
          version = "1.0.0";
          src = self;
          nativeBuildInputs = gleamDeps pkgs;
          buildPhase = ''
            export HOME=$TMPDIR
            cd infra
            mkdir -p build/packages
            cp -r ${self.packages.${system}.deps}/* build/packages/
            chmod -R u+w build/packages
            gleam export erlang-shipment
          '';
          installPhase = "cp -r build/erlang-shipment $out";
        };
      });

      apps = eachSystem (system: pkgs: {
        default = {
          type = "app";
          program = toString (pkgs.writeShellScript "infra" ''
            cd infra
            exec ${self.packages.${system}.default}/entrypoint.sh run
          '');
        };
      });

      devShells = eachSystem (_system: pkgs: {
        default = pkgs.mkShell { packages = gleamDeps pkgs; };
      });
    };
}
