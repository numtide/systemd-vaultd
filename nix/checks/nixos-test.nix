{
  makeTest ? import <nixpkgs/nixos/tests/make-test-python.nix>,
  pkgs ? (import <nixpkgs> {}),
  vaultAgent ? ../modules/vault-agent.nix,
  systemdVaultd ? ../modules/systemd-vaultd.nix,
}: let
  makeTest' = args:
    makeTest args {
      inherit pkgs;
      inherit (pkgs) system;
    };
in {
  vault-agent = makeTest' {
    name = "vault-agent";
    nodes.server = {
      config,
      pkgs,
      ...
    }: {
      imports = [
        vaultAgent
        ./dev-vault-server.nix
      ];

      services.vault.agents.test.settings = {
        vault = {
          address = "http://localhost:8200";
        };
        template = {
          contents = ''{{ with secret "secret/my-secret" }}{{ .Data.data.foo }}{{ end }}'';
          destination = "/run/render.txt";
        };

        auto_auth = {
          method = [
            {
              type = "approle";
              config = {
                role_id_file_path = "/tmp/roleID";
                secret_id_file_path = "/tmp/secretID";
              };
            }
          ];
        };
      };
    };
    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("vault.service")
      machine.wait_for_open_port(8200)
      machine.wait_for_unit("setup-vault-agent-approle.service")

      # It should be able to write our template
      out = machine.wait_until_succeeds("cat /run/render.txt")
      print(out)
      assert out == "bar"
    '';
  };
  systemd-vaultd = makeTest' {
    name = "systemd-vaultd";
    nodes.server = {
      config,
      pkgs,
      ...
    }: {
      imports = [
        vaultAgent
        systemdVaultd
        ./dev-vault-server.nix
      ];

      systemd.services.service1 = {
        wantedBy = ["multi-user.target"];
        script = ''
          cat $CREDENTIALS_DIRECTORY/secret > /tmp/service1
        '';
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          LoadCredential = ["secret:/run/systemd-vaultd/sock"];
        };
      };

      systemd.services.service2 = {
        wantedBy = ["multi-user.target"];
        script = ''
          cat $CREDENTIALS_DIRECTORY/secret > /tmp/service2
        '';
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          LoadCredential = ["secret:/run/systemd-vaultd/sock"];
        };
      };

      services.vault.agents.test.settings = {
        vault = {
          address = "http://localhost:8200";
        };
        template = [
          {
            contents = ''{{ with secret "secret/my-secret" }}{{ .Data.data.foo }}{{ end }}'';
            destination = "/run/systemd-vaultd/secrets/service1.service-secret";
          }
          {
            contents = ''{{ with secret "secret/blocking-secret" }}{{ .Data.data.foo }}{{ end }}'';
            destination = "/run/systemd-vaultd/secrets/service2.service-secret";
          }
        ];

        auto_auth = {
          method = [
            {
              type = "approle";
              config = {
                role_id_file_path = "/tmp/roleID";
                secret_id_file_path = "/tmp/secretID";
              };
            }
          ];
        };
      };
    };
    testScript = ''
      start_all()
      machine.wait_for_unit("vault.service")
      machine.wait_for_open_port(8200)
      machine.wait_for_unit("setup-vault-agent-approle.service")
      machine.wait_for_unit("service1.service")
      out = machine.succeed("cat /tmp/service1")
      print(out)
      assert out == "bar"
      out = machine.succeed("systemctl list-jobs")
      print(out)
      assert "service2.service" in out, "service2 should be still blocked"
      machine.succeed("vault kv put secret/blocking-secret foo=bar")
      machine.wait_for_unit("service2.service")
    '';
  };
  unittests = makeTest' {
    name = "unittests";
    nodes.server = {};

    testScript = ''
      start_all()
      server.succeed("machinectl shell .host ${pkgs.callPackage ./unittests.nix {}} >&2")
      # machinectl does not passthru exit codes, so we have to check manually
      server.succeed("[[ -f /tmp/success ]]")
    '';
  };
}
