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
                remove_secret_id_file_after_reading = false;
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
          cat $CREDENTIALS_DIRECTORY/foo > /tmp/service1
        '';
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        vault = {
          template = ''
            {{ with secret "secret/my-secret" }}{{ .Data.data | toJSON }}{{ end }}
          '';
          secrets.foo = {};
        };
      };

      systemd.services.service2 = {
        wantedBy = ["multi-user.target"];
        script = ''
          cat $CREDENTIALS_DIRECTORY/secret > /tmp/service2
          sleep infinity
        '';
        reload = ''
          cat $CREDENTIALS_DIRECTORY/secret > /tmp/service2-reload
        '';
        serviceConfig.LoadCredential = ["secret:/run/systemd-vaultd/sock"];
        vault = {
          template = ''
            {{ with secret "secret/blocking-secret" }}{{ scratch.MapSet "secrets" "secret" .Data.data.foo }}{{ end }}
            {{ scratch.Get "secrets" | explodeMap | toJSON }}
          '';
          secrets.secret = {};
        };
      };

      systemd.package = pkgs.systemd.overrideAttrs (old: {
        patches =
          old.patches
          ++ [
            (pkgs.fetchpatch {
              url = "https://github.com/Mic92/systemd/commit/93a2921a81cab3be9b7eacab6b0095c96a0ae9e2.patch";
              sha256 = "sha256-7WlhMLE7sfD3Cxn6n6R1sUNzUOvas7XMyabi3bsq7jM=";
            })
          ];
      });

      services.vault.agents.default.settings = {
        vault = {
          address = "http://localhost:8200";
        };
        auto_auth = {
          method = [
            {
              type = "approle";
              config = {
                role_id_file_path = "/tmp/roleID";
                secret_id_file_path = "/tmp/secretID";
                remove_secret_id_file_after_reading = false;
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
      assert out == "bar", f"{out} != bar"

      out = machine.succeed("systemctl status service2")
      print(out)
      assert "(sd-mkdcreds)" in out, "service2 should be still blocked"

      machine.succeed("vault kv put secret/blocking-secret foo=bar")
      out = machine.wait_until_succeeds("cat /tmp/service2")
      print(out)
      assert out == "bar", f"{out} != bar"

      machine.succeed("vault kv put secret/blocking-secret foo=reload")
      machine.succeed("rm /run/systemd-vaultd/secrets/service2.service.json")
      machine.succeed("systemctl restart vault-agent-default")
      machine.wait_until_succeeds("cat /run/systemd-vaultd/secrets/service2.service.json >&2")
      machine.succeed("systemctl reload service2")
      out = machine.wait_until_succeeds("cat /tmp/service2-reload")
      print(out)
      assert out == "reload", f"{out} != reload"
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
