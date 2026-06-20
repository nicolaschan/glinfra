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

      # Names of the in-repo path dependencies. Gleam fingerprints each path
      # dep's gleam.toml to detect changes; we synthesize those fingerprint
      # files below so it never re-resolves (see configurePhase).
      localDepNames = map ({ name, ... }: name)
        (builtins.filter ({ source, ... }: source == "local") manifest.packages);

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
          nativeBuildInputs = (gleamBuildInputs pkgs) ++ [ pkgs.xxhash ];
          configurePhase = ''
            export HOME=$TMPDIR
            cd infra
            rm -rf build
            mkdir build
            cp -r --no-preserve=mode --dereference ${mkPackagesDir pkgs} build/packages

            # Gleam would otherwise re-resolve dependency versions on every
            # build, and resolution reaches the network (the hex registry and a
            # git fetch for git deps) — unavailable in the sandbox. It skips
            # resolution when every path dep is unchanged, which it decides by
            # comparing a stored `<name>.config_fingerprint` against the xxh3_64
            # of that dep's gleam.toml (gleam's SourceFingerprint). The committed
            # manifest.toml already pins the exact versions of the pre-fetched
            # packages, so write the fingerprint gleam itself would compute. A
            # future gleam that changes this fails loudly here (re-resolve ->
            # sandbox network error), never silently producing a wrong build.
            for dep in ${builtins.concatStringsSep " " localDepNames}; do
              hex=$(xxhsum -H3 "build/packages/$dep/gleam.toml" | cut -d' ' -f1)
              printf '%llu' "0x''${hex#XXH3_}" > "build/packages/$dep.config_fingerprint"
            done
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
          # The erlang-shipment's entrypoint shells out to `erl`, so provide
          # Erlang on PATH rather than depending on the user having it. The
          # generator writes into the surrounding checkout (paths relative to
          # ../, see glinfra/compile.repo_path_to_fs), so it must run from the
          # repo's infra/ directory — hence `cd infra`.
          program = toString (pkgs.writeShellScript "infra" ''
            export PATH=${pkgs.lib.makeBinPath [ pkgs.erlang ]}''${PATH:+:$PATH}
            cd infra
            exec ${self.packages.${system}.default}/entrypoint.sh run
          '');
        };
      });

      devShells = eachSystem (_system: pkgs: {
        default = pkgs.mkShell { packages = (gleamBuildInputs pkgs) ++ (with pkgs; [ fluxcd k9s ]); };
      });
    };
}
