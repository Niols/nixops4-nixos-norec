{
  config,
  inputs,
  lib,
  providers,
  withResourceProviderSystem,
  ...
}:
let
  pubKeysFile = ./deployer.pub;
  inherit (lib) mkOption types;
in
{
  options = {
    hostPort = mkOption {
      type = types.int;
      default = 2222;
    };
    hostName = mkOption {
      type = types.str;
      default = "127.0.0.1";
    };
  };
  config = {
    providers.local = inputs.nixops4.modules.nixops4Provider.local;
    resources.hello = {
      type = providers.local.exec;
      inputs = {
        executable = withResourceProviderSystem ({ pkgs, ... }: lib.getExe pkgs.hello);
        args = [
          "--greeting"
          "Hallo wereld"
        ];
      };
    };
    resources.nixos = {
      type = providers.local.exec;
      imports = [
        inputs.nixops4-nixos.modules.nixops4Resource.nixos
      ];

      nixpkgs = inputs.nixpkgs;
      nixos.module =
        { pkgs, modulesPath, ... }:
        {
          imports = [
            # begin hardware config
            (modulesPath + "/profiles/qemu-guest.nix")
            (modulesPath + "/../lib/testing/nixos-test-base.nix")
            {
              # See test/default/nixosTest.nix
              system.switch.enable = true;
              # Not used; save a large copy operation
              nix.channel.enable = false;
              nix.registry = lib.mkForce { };
            }
            # end hardware config
          ];

          nixpkgs.hostPlatform = "x86_64-linux";

          services.openssh.enable = true;
          services.openssh.settings.PermitRootLogin = "yes";
          networking.firewall.allowedTCPPorts = [ 22 ];

          users.users.root.openssh.authorizedKeys.keyFiles = [ pubKeysFile ];
          users.users.root.initialPassword = "asdf";
          users.users.bossmang.openssh.authorizedKeys.keyFiles = [ pubKeysFile ];
          users.users.bossmang.isNormalUser = true;
          users.users.bossmang.group = "bossmang";
          users.users.bossmang.extraGroups = [ "wheel" ];
          users.groups.bossmang = { };

          security.sudo.execWheelOnly = true; # hardening
          security.sudo.wheelNeedsPassword = false; # can not be entered through NixOps

          # end hardware config

          environment.etc."greeting".text = config.resources.hello.outputs.stdout;
          environment.systemPackages = [
            pkgs.hello
          ];
        };

      ssh.opts = "-o Port=${toString config.hostPort}";
      ssh.host = config.hostName;
      ssh.hostPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAiszi43aOWWV7voNgQ1Ifa7LGKwGJfOuiLM1n42h2Y8";
    };
  };
}
