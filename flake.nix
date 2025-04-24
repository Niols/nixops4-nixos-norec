{
  inputs = {
    # nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs.follows = "nixops4/nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks.url = "github:cachix/git-hooks.nix";
    agenix.url = "github:ryantm/agenix";
    disko.url = "github:nix-community/disko";
    nixops4.url = "github:nixops4/nixops4";
    nixops4-nixos.url = "github:nixops4/nixops4-nixos";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = ["x86_64-linux"];

      imports = [
        inputs.nixops4.modules.flake.default
        ./deployment/test/nixops4/flake-part.nix
      ];
    };
}
