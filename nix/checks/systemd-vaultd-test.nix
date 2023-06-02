{
  name = "systemd-vaultd";
  nodes.server =
    { config
    , ...
    }: {
      imports = [
        ../modules/vault-agent.nix
        ../modules/systemd-vaultd.nix
        ./dev-vault-server.nix
      ];
      # speed up tests
      virtualisation.cores = 4;
      virtualisation.memorySize = 1024;

      systemd.services.service1 = {
        wantedBy = [ "multi-user.target" ];
        script = ''
          cat $CREDENTIALS_DIRECTORY/foo > /tmp/service1
          echo -n "$SECRET_ENV" > /tmp/service1-env
        '';
        #serviceConfig = {
        #  EnvironmentFile = [ "/run/systemd-vaultd/service1.service.EnvironmentFile" ];
        #};
        vault = {
          template = ''
            {{ with secret "secret/my-secret" }}{{ .Data.data | toJSON }}{{ end }}
          '';
          secrets.foo = { };
          environmentTemplate = ''
            {{ with secret "secret/my-secret" }}
            SECRET_ENV={{ .Data.data.foo }}
            {{ end }}
          '';
        };
      };

      users.users.service2 = {
        isSystemUser = true;
        group = "service2";
        uid = 1000;
      };
      users.groups.service2.gid = 1000;

      systemd.services.service2 = {
        wantedBy = [ "multi-user.target" ];
        preStart = ''
          cp -r $CREDENTIALS_DIRECTORY /run/service2/secrets
        '';
        script = ''
          set -x
          while true; do
            cat /run/service2/secrets/secret >&2 || :
            cat /run/service2/secrets/secret > /tmp/service2 || :
            sleep 0.1
          done
        '';
        serviceConfig = {
          ExecReload = "+${config.services.systemd-vaultd.package}/bin/systemd-vaultd-update-secrets /run/service2/secrets";
          User = "service2";
          Group = "service2";
          LoadCredential = [ "secret:/run/systemd-vaultd/sock" ];
          RuntimeDirectory = "service2";
        };
        vault = {
          template = ''
            {{ with secret "secret/blocking-secret" }}{{ scratch.MapSet "secrets" "secret" .Data.data.foo }}{{ end }}
            {{ scratch.Get "secrets" | explodeMap | toJSON }}
          '';
          secrets.secret = { };
        };
      };

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
    machine.wait_for_unit("vault-agent-default.service")

    out = machine.wait_until_succeeds("grep -q bar /tmp/service1")

    out = machine.succeed("grep -q bar /tmp/service1-env")

    out = machine.succeed("systemctl status service2 || :")
    print(out)
    assert "(sd-mkdcreds)" in out, "service2 should be still blocked"

    machine.succeed("vault kv put secret/blocking-secret foo=bar")
    machine.wait_until_succeeds("grep -q bar /tmp/service2 >&2")

    machine.succeed("umount /run/credentials/service2.service")
    machine.succeed("rm /run/systemd-vaultd/secrets/service2.service.json")

    machine.succeed("vault kv put secret/blocking-secret foo=reload")

    machine.succeed("systemctl restart vault-agent-default")
    machine.wait_until_succeeds("cat /run/systemd-vaultd/secrets/service2.service.json >&2")
    machine.succeed("systemctl restart service2")

    machine.succeed("rm /tmp/service2")
    machine.wait_until_succeeds("grep -q reload /tmp/service2 >&2")

    # get uid and gid
    out = machine.succeed("stat -c %u /run/service2/secrets/secret").strip()
    assert out == "1000", "service2 should have access to secret file with uid 1000, got " + out
    out = machine.succeed("stat -c %g /run/service2/secrets/secret").strip()
    assert out == "1000", "service2 should have access to secret file with gid 1000, got " + out

    # get permissions in octal
    out = machine.succeed("stat -c %a /run/service2/secrets/secret").strip()
    assert out == "400", "service2 should have access to secret file with permissions 0400, got " + out
  '';
}
