{
  name = "systemd-vaultd";
  nodes.server =
    { config
    , pkgs
    , ...
    }: {
      imports = [
        ../modules/vault-agent.nix
        ../modules/systemd-vaultd.nix
        ./dev-vault-server.nix
      ];

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

      systemd.services.service2 = {
        wantedBy = [ "multi-user.target" ];
        script = ''
          set -x
          while true; do
            cat $CREDENTIALS_DIRECTORY/secret > /tmp/service2
            sleep 0.1
          done
        '';
        serviceConfig.ExecReload = "${pkgs.coreutils}/bin/true";
        serviceConfig.LoadCredential = [ "secret:/run/systemd-vaultd/sock" ];
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

    out = machine.wait_until_succeeds("cat /tmp/service1")
    print(out)
    assert out == "bar", f"{out} != bar"

    out = machine.succeed("cat /tmp/service1-env")
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

    machine.succeed("rm /tmp/service2")
    out = machine.wait_until_succeeds("cat /tmp/service2")
    print(out)
    assert out == "reload", f"{out} != reload"
  '';
}
