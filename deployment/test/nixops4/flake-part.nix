{ inputs, ... }:

{
  nixops4Deployments.deployment-test-nixops4 =
    { ... }:
    {
      imports = [
        ./deployment.nix
        ./deployment-for-test.nix
      ];
      _module.args.inputs = inputs;
    };

  perSystem = { inputs', pkgs, ... }: {
    checks.deployment-test-nixops4 = pkgs.callPackage ./nixosTest.nix {
      nixops4-flake-in-a-bottle = inputs'.nixops4.packages.flake-in-a-bottle;
      inherit inputs;
    };
  };
}
