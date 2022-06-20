{
  makeTest ? import <nixpkgs/nixos/tests/make-test-python.nix>,
  pkgs ? (import <nixpkgs> {}),
  vaultAgentModule ? ../modules/vault-agent.nix
}: let
  makeTest' = args:
    makeTest args {
      inherit pkgs;
      inherit (pkgs) system;
    };
in {
  vault-agent = makeTest' {
    name = "vault-agent";
    nodes.server = {config, pkgs, ...}: {
      imports = [
        vaultAgentModule
      ];

      environment.systemPackages = [ pkgs.vault ];
      services.vault = {
        enable = true;
        dev = true;
        devRootTokenID = "phony-secret";
      };
      systemd.services.setup-vault-agent-approle = {
        path = [ pkgs.jq pkgs.vault pkgs.systemd ];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = "yes";
          Environment = [
            "VAULT_TOKEN=${config.services.vault.devRootTokenID}"
            "VAULT_ADDR=http://127.0.0.1:8200"
          ];
        };

        script = ''
          set -eux -o pipefail
          while ! vault status; do
            sleep 1
          done

          # capabilities of our vault agent
          cat > /tmp/policy-file.hcl <<EOF
          path "secret/data/my-secret" {
            capabilities = ["read"]
          }
          EOF
          vault policy write demo /tmp/policy-file.hcl
          vault kv put secret/my-secret foo=bar

          # role for our vault agent
          vault auth enable approle
          vault write auth/approle/role/role1 bind_secret_id=true token_policies=demo
          echo -n $(vault read -format json auth/approle/role/role1/role-id | jq -r .data.role_id) > /tmp/roleID
          echo -n $(vault write -force -format json auth/approle/role/role1/secret-id | jq -r .data.secret_id) > /tmp/secretID
        '';
      };
      # Make sure our setup service is started before our vault-agent
      systemd.services.vault-agent-test = {
        wants = [ "setup-vault-agent-approle.service" ];
        after = [ "setup-vault-agent-approle.service" ];
      };
      services.vault.agents.test.settings = {
        vault = {
          address = "http://localhost:8200";
        };
        template = {
          contents = ''{{ with secret "secret/my-secret" }}{{ .Data.data.foo }}{{ end }}'';
          destination = "/run/render.txt";
        };

        auto_auth = {
          method = [{
            type = "approle";
            config = {
              role_id_file_path = "/tmp/roleID";
              secret_id_file_path = "/tmp/secretID";
            };
          }];
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
