/**
  This module is loaded by the integration test.
  See `flake-module`, where it's imported into `nixops4Deployments.test`.
*/
{
  # Example of explicit configuration
  hostPort = 22;
  hostName = "target";

  imports = [
    # The test will generate some deep overrides for things like the host public key.
    ./generated.nix
  ];

  # Test VMs doesn't have a bootloader by default.
  resources.nixos.nixos.module.boot.loader.grub.enable = false;
}
