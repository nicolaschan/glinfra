{
  description = "glinfra";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      eachSystem = f: nixpkgs.lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
      gleamBuildInputs = pkgs: with pkgs; [ gleam erlang rebar3 ];

      # Read manifest.toml at Nix eval time to get package checksums.
      # No manual hash management needed — checksums come from manifest.toml.
      manifest = builtins.fromTOML (builtins.readFile ./infra/manifest.toml);

      # Assemble the build/packages directory using fetchHex + linkFarm.
      mkPackagesDir = pkgs:
        let
          fetchedPackages = builtins.concatMap
            ({ name, version, source, ... }@pkg:
              if source == "hex" then [{
                inherit name;
                path = pkgs.fetchHex {
                  pkg = name;
                  inherit version;
                  sha256 = pkg.outer_checksum;
                };
              }]
              else if source == "git" then [{
                inherit name;
                path = builtins.fetchGit {
                  url = pkg.repo;
                  rev = pkg.commit;
                };
              }]
              else if source == "local" then [{
                inherit name;
                path = self + "/infra/${pkg.path}";
              }]
              else throw "glinfra: unsupported dep source '${source}'"
            )
            manifest.packages;

          # Generate a deterministic packages.toml (Gleam's is non-deterministic).
          packagesTOML = (pkgs.formats.toml { }).generate "packages.toml" {
            packages = builtins.listToAttrs (
              map ({ name, version, ... }: { inherit name; value = version; })
                manifest.packages
            );
          };
        in
        pkgs.linkFarm "glinfra-packages" (fetchedPackages ++ [
          { name = "packages.toml"; path = packagesTOML; }
        ]);
    in
    {
      packages = eachSystem (system: pkgs: {
        default = pkgs.stdenv.mkDerivation {
          pname = "infra";
          version = "1.0.0";
          src = self;
          nativeBuildInputs = gleamBuildInputs pkgs;
          configurePhase = ''
            export HOME=$TMPDIR
            cd infra
            rm -rf build
            mkdir build
            cp -r --no-preserve=mode --dereference ${mkPackagesDir pkgs} build/packages
          '';
          buildPhase = ''
            gleam export erlang-shipment
          '';
          installPhase = ''
            cp -r build/erlang-shipment $out
          '';
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
        default = pkgs.mkShell { packages = gleamBuildInputs pkgs; };
      });
    };
}
