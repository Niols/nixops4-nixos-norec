{
  testers,
  inputs,
  runCommandNoCC,
  nixops4-flake-in-a-bottle,
  ...
}:

testers.runNixOSTest (
  {
    lib,
    config,
    hostPkgs,
    ...
  }:
  let
    vmSystem = config.node.pkgs.hostPlatform.system;

    # TODO turn deployment/test/nixops4 directory into a flake, and refer to the whole repo only
    #      as a flake input
    src = lib.fileset.toSource {
      fileset = ../../..;
      root = ../../..;
    };

    ## We will need to override some inputs by the empty flake, so we make one.
    emptyFlake = runCommandNoCC "empty-flake" { } ''
      mkdir $out
      echo "{ outputs = { self }: {}; }" > $out/flake.nix
    '';

    targetNetworkJSON = hostPkgs.writeText "target-network.json" (
      builtins.toJSON config.nodes.target.system.build.networkConfig
    );

  in
  {
    name = "nixops4-nixos";
    imports = [
      inputs.nixops4-nixos.modules.nixosTest.static
    ];

    nodes = {
      deployer =
        { pkgs, nodes, ... }:
        {
          environment.systemPackages = [
            inputs.nixops4.packages.${vmSystem}.default
          ];
          # Memory use is expected to be dominated by the NixOS evaluation, which
          # happens on the deployer.
          virtualisation.memorySize = 4096;
          virtualisation.diskSize = 10 * 1024;
          virtualisation.cores = 2;
          nix.settings = {
            substituters = lib.mkForce [ ];
            hashed-mirrors = null;
            connect-timeout = 1;
          };
          system.extraDependencies =
            [
              "${inputs.flake-parts}"
              "${inputs.flake-parts.inputs.nixpkgs-lib}"
              "${inputs.nixops4}"
              "${inputs.nixops4-nixos}"
              "${inputs.nixpkgs}"
              pkgs.stdenv
              pkgs.stdenvNoCC
              pkgs.hello
              # Some derivations will be different compared to target's initial state,
              # so we'll need to be able to build something similar.
              # Generally the derivation inputs aren't that different, so we use the
              # initial state of the target as a base.
              nodes.target.system.build.toplevel.inputDerivation
              nodes.target.system.build.etc.inputDerivation
              nodes.target.system.path.inputDerivation
              nodes.target.system.build.bootStage1.inputDerivation
              nodes.target.system.build.bootStage2.inputDerivation
            ]
            ++ lib.concatLists (
              lib.mapAttrsToList (
                k: v: if v ? source.inputDerivation then [ v.source.inputDerivation ] else [ ]
              ) nodes.target.environment.etc
            );
        };
      target = {
        # Test framework disables switching by default. That might be ok by itself,
        # but we also use this config for getting the dependencies in
        # `deployer.system.extraDependencies`.
        system.switch.enable = true;
        # Not used; save a large copy operation
        nix.channel.enable = false;
        nix.registry = lib.mkForce { };

        services.openssh.enable = true;
      };
    };

    testScript = ''
      start_all()
      target.wait_for_unit("multi-user.target")
      deployer.wait_for_unit("multi-user.target")

      # This mysteriously doesn't work.
      # target.wait_for_unit("network-online.target")
      # deployer.wait_for_unit("network-online.target")

      with subtest("unpacking"):
        deployer.succeed("""
          cp -r --no-preserve=mode ${src} work
        """)

      with subtest("configure the deployment"):
        deployer.copy_from_host("${targetNetworkJSON}", "/root/target-network.json")
        deployer.succeed("""
          (
            cd work
            set -x
            mkdir -p ~/.ssh
            ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
            mv /root/target-network.json deployment/test/nixops4/target-network.json
          )
        """)
        deployer_public_key = deployer.succeed("cat ~/.ssh/id_rsa.pub").strip()
        target.succeed("mkdir -p /root/.ssh && echo '{}' >> /root/.ssh/authorized_keys".format(deployer_public_key))
        host_public_key = target.succeed("ssh-keyscan target | grep -v '^#' | cut -f 2- -d ' ' | head -n 1")
        generated_config = f"""
          {{ lib, ... }}: {{
            imports = [ ./extra-deployment-config.nix ];
            resources.nixos.ssh.hostPublicKey = lib.mkForce "{host_public_key}";
            resources.nixos.nixos.module = {{
              imports = [
                (lib.modules.importJSON ./target-network.json)
              ];
            }};
          }}
          """
        deployer.succeed(f"""cat > work/deployment/test/nixops4/generated.nix <<"_EOF_"\n{generated_config}\n_EOF_\n""")
        deployer.succeed("""
          cp ~/.ssh/id_rsa.pub work/deployment/test/nixops4/deployer.pub
          cat -n work/deployment/test/nixops4/generated.nix 1>&2;
          echo {} > work/deployment/test/nixops4/extra-deployment-config.nix
          # Fail early if we made a syntax mistake in generated.nix. (following commands may be slow)
          nix-instantiate work/deployment/test/nixops4/generated.nix --eval --parse >/dev/null
        """)

      # This is slow, but could be optimized in Nix.
      # TODO: when not slow, do right after unpacking work/
      with subtest("override the lock"):
        deployer.succeed("""
          (
            cd work
            set -x
            nix flake lock --extra-experimental-features 'flakes nix-command' \
              --offline -v \
              --override-input flake-parts ${inputs.flake-parts} \
              --override-input nixops4 ${nixops4-flake-in-a-bottle} \
              \
              --override-input nixops4-nixos ${inputs.nixops4-nixos} \
              --override-input nixops4-nixos/flake-parts ${inputs.nixops4-nixos.inputs.flake-parts} \
              --override-input nixops4-nixos/flake-parts/nixpkgs-lib ${inputs.nixops4-nixos.inputs.flake-parts.inputs.nixpkgs-lib} \
              --override-input nixops4-nixos/nixops4-nixos ${emptyFlake} \
              --override-input nixops4-nixos/nixpkgs ${inputs.nixops4-nixos.inputs.nixpkgs} \
              --override-input nixops4-nixos/nixops4 ${nixops4-flake-in-a-bottle} \
              --override-input nixops4-nixos/git-hooks-nix ${emptyFlake} \
              \
              --override-input nixpkgs ${inputs.nixpkgs} \
              --override-input git-hooks ${inputs.git-hooks} \
              ;
          )
        """)

      with subtest("nixops4 apply"):
        deployer.succeed("""
          (
            cd work
            set -x
            # "test" is the name of the deployment
            nixops4 apply deployment-test-nixops4 --show-trace
          )
        """)

      with subtest("check the deployment"):
        target.succeed("""
          (
            set -x
            hello 1>&2
          )
        """)
        target.succeed("""
          (
            set -x
            cat -n /etc/greeting 1>&2
            echo "Hallo wereld" | diff /etc/greeting - 1>&2
          )
        """)

      with subtest("nixops4 apply as user"):
        extra_config = """
          { lib, ... }: {
            resources.nixos.ssh.user = "bossmang";
          }
          """
        deployer.succeed(f"""cat > work/deployment/test/nixops4/extra-deployment-config.nix <<"_EOF_"\n{extra_config}\n_EOF_\n""")
        deployer.succeed("""
          (
            cd work
            set -x
            nixops4 apply deployment-test-nixops4 --show-trace
          )
        """)

      with subtest("use ssh ambient user"):
        with subtest("set up to deny root login"):
          with subtest("configure deployment to deny root login on target"):
            extra_config = """
              { lib, ... }: {
                resources.nixos.nixos.module.services.openssh.settings.PermitRootLogin = lib.mkForce "no";
              }
              """
            deployer.succeed(f"""cat > work/deployment/test/nixops4/extra-deployment-config.nix <<"_EOF_"\n{extra_config}\n_EOF_\n""")
          with subtest("nixops4 apply"):
            deployer.succeed("""
              (
                cd work
                set -x
                nixops4 apply deployment-test-nixops4 --show-trace
              )
            """)
          with subtest("check assumption: root is denied"):
            deployer.succeed(f"""
              (
                set -x
                echo "target {host_public_key}" > target-host-key
                # assume pipefail semantics
                ! ( false | true )
                (
                  set +e
                  ssh -o ConnectTimeout=10 \
                      -o ConnectionAttempts=12 \
                      -o KbdInteractiveAuthentication=no \
                      -o PasswordAuthentication=no \
                      -o UserKnownHostsFile="$PWD/target-host-key" \
                      -o StrictHostKeyChecking=yes \
                      -v \
                      2>&1 \
                    target \
                    true
                  r=$?
                  echo "ssh exit status: $r" 1>&2
                  [[ $r -eq 255 ]]
                ) | tee ssh.log
                grep -F 'root@target: Permission denied (' ssh.log
                rm ssh.log
              )
            """)
          with subtest("configure user in ~/.ssh/config"):
            deployer.succeed("""
              mkdir -p ~/.ssh
              (
                echo 'Host target'
                echo '  User bossmang'
              ) > ~/.ssh/config
              cat -n ~/.ssh/config
            """)
          with subtest("check assumption: user is allowed"):
            deployer.succeed(f"""
              (
                set -x
                echo "target {host_public_key}" > target-host-key
                ssh -o ConnectTimeout=10 \
                    -o ConnectionAttempts=12 \
                    -o KbdInteractiveAuthentication=no \
                    -o PasswordAuthentication=no \
                    -o UserKnownHostsFile="$PWD/target-host-key" \
                    -o StrictHostKeyChecking=yes \
                    -v \
                    2>&1 \
                  target \
                  true
              )
            """)
          with subtest("clean up"):
            deployer.succeed("""
              rm ~/.ssh/config
            """)

        with subtest("check error propagation through resource and nixops4"):
          deployer.succeed("""
            (
              cd work
              set -x
              (
                set +e
                nixops4 apply deployment-test-nixops4 --show-trace 2>&1
                r=$?
                echo "nixops4 exit status: $r" 1>&2
                [[ $r -eq 1 ]]
              ) | tee nixops4.log
              grep -F 'root@target: Permission denied' nixops4.log
              rm nixops4.log
            )
          """)

        with subtest("configure user in ~/.ssh/config"):
          deployer.succeed("""
            mkdir -p ~/.ssh
            (
              echo 'Host target'
              echo '  User bossmang'
            ) > ~/.ssh/config
            cat -n ~/.ssh/config
          """)

        with subtest("configure deployment to use ambient user"):
          extra_config = """
            { lib, ... }: {
              resources.nixos.nixos.module.services.openssh.settings.PermitRootLogin = lib.mkForce "no";
              resources.nixos.ssh.user = null;
            }
            """
          deployer.succeed(f"""cat > work/deployment/test/nixops4/extra-deployment-config.nix <<"_EOF_"\n{extra_config}\n_EOF_\n""")

        with subtest("can deploy with ambient user setting"):
          deployer.succeed("""
            (
              cd work
              set -x
              nixops4 apply deployment-test-nixops4 --show-trace
            )
          """)


      # TODO: nixops4 run feature, calling ssh
    '';
  }
)
