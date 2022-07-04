{
  config,
  lib,
  pkgs,
  ...
}: {
  environment.systemPackages = [pkgs.vault];
  services.vault = {
    enable = true;
    dev = true;
    devRootTokenID = "phony-secret";
  };
  environment.variables.VAULT_ADDR = "http://127.0.0.1:8200";
  environment.variables.VAULT_TOKEN = config.services.vault.devRootTokenID;

  systemd.services.setup-vault-agent-approle = {
    path = [pkgs.jq pkgs.vault pkgs.systemd];
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      Environment = [
        "VAULT_TOKEN=${config.environment.variables.VAULT_TOKEN}"
        "VAULT_ADDR=${config.environment.variables.VAULT_ADDR}"
      ];
    };

    script = ''
      set -eux -o pipefail
      while ! vault status; do
        sleep 1
      done

      # capabilities of our vault agent
      cat > /tmp/policy-file.hcl <<EOF
      path "secret/data/*" {
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
    wants = ["setup-vault-agent-approle.service"];
    after = ["setup-vault-agent-approle.service"];
  };
}
