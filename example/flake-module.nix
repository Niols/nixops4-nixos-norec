{ inputs, ... }:
{
  imports = [ inputs.nixops4.modules.flake.default ];
  nixops4Deployments.default =
    { ... }:
    {
      imports = [
        ./deployment.nix
      ];
      _module.args.inputs = inputs;
    };
  nixops4Deployments.test =
    { ... }:
    {
      imports = [
        ./deployment.nix
        ./deployment-for-test.nix
      ];
      _module.args.inputs = inputs;
    };
}
