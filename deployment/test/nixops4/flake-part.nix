{ inputs, ... }:

{
  nixops4Deployments.test =
    { ... }:
    {
      imports = [
        ./deployment.nix
        ./deployment-for-test.nix
      ];
      _module.args.inputs = inputs;
    };

  perSystem = { inputs', pkgs, ... }: {
    checks.default = pkgs.callPackage ./nixosTest.nix {
      nixops4-flake-in-a-bottle = inputs'.nixops4.packages.flake-in-a-bottle;
      inherit inputs;
    };
  };
}
