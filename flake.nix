{
  description = "NixOS integration for NixOps4";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixops4-nixos.url = "github:nixops4/nixops4-nixos";

    # Dev dependencies
    # These need to be in the main flake for now, because we can't easily pre-fetch the private flake-compat dependency in flake-parts.
    # TODO: We could wait for https://github.com/NixOS/nix/issues/7730 or
    #       1. put a ?narHash= in flake-parts or vendor flake-compat there
    #       2. partitions.dev.extraInputsFlake = ./dev;
    nixpkgs.follows = "nixops4/nixpkgs";
    nixops4.url = "github:nixops4/nixops4";
    git-hooks-nix.url = "github:cachix/git-hooks.nix";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = ["x86_64-linux"];

      imports = [
        inputs.nixops4.modules.flake.default
        ./test/default/flake-module.nix
      ];
    };
}
