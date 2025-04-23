{
  description = "NixOS integration for NixOps4";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";

    # Dev dependencies
    # These need to be in the main flake for now, because we can't easily pre-fetch the private flake-compat dependency in flake-parts.
    # TODO: We could wait for https://github.com/NixOS/nix/issues/7730 or
    #       1. put a ?narHash= in flake-parts or vendor flake-compat there
    #       2. partitions.dev.extraInputsFlake = ./dev;
    nixpkgs.follows = "nixops4/nixpkgs";
    nixops4.url = "github:nixops4/nixops4";
    git-hooks-nix.url = "github:cachix/git-hooks.nix";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    {
      inherit
        (flake-parts.lib.mkFlake { inherit inputs; } {
          imports = [
            inputs.flake-parts.flakeModules.partitions
            inputs.flake-parts.flakeModules.modules
            ./main-module.nix
          ];
          systems = [
            "x86_64-linux"
            "aarch64-linux"
            "aarch64-darwin"
            "x86_64-darwin"
          ];
          partitions.dev.module = {
            imports = [
              ./dev/flake-module.nix
              ./example/flake-module.nix
            ];
          };
          partitionedAttrs.devShells = "dev";
          partitionedAttrs.checks = "dev";
          partitionedAttrs.nixops4Deployments = "dev";
          partitionedAttrs.herculesCI = "dev";
        })
        modules
        devShells
        checks
        /**
          Example configurations used in integration tests.
        */
        nixops4Deployments
        /**
          Continuous integration settings
        */
        herculesCI
        ;
    };
}
