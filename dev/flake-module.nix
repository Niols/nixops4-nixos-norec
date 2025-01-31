{ inputs, ... }:
{
  imports = [
    inputs.git-hooks-nix.flakeModule
  ];
  flake.herculesCI.ciSystems = [ "x86_64-linux" ];
  perSystem =
    {
      config,
      inputs',
      pkgs,
      ...
    }:
    {
      checks = {
        default = pkgs.callPackage ../test/default/nixosTest.nix {
          nixops4-flake-in-a-bottle = inputs'.nixops4.packages.flake-in-a-bottle;
          inherit inputs;
        };
      };
      devShells.default = pkgs.mkShellNoCC {
        nativeBuildInputs = [
          pkgs.nixfmt-rfc-style
          inputs'.nixops4.packages.default
        ];
        shellHook = ''
          ${config.pre-commit.settings.installationScript}
        '';
      };
      packages.nixops4-flake-in-a-bottle = pkgs.callPackage ../test/nixops4-flake-in-a-bottle/stuff.nix {
        nixops4Flake = inputs.nixops4;
      };
      pre-commit.settings.hooks.nixfmt-rfc-style.enable = true;
    };
}
