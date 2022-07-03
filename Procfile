vault: vault server -dev -dev-root-token-id secret
vault-agent:  sleep 10 && ./tests/setup-vault && sudo vault agent -config ./tests/vault-agent-example.hcl
systemd-vaultd:  rm -rf /run/systemd-vault/secrets && sudo ./systemd-vaultd
systemd-service:  sudo systemd-run --collect -u vault-nixos3.service -p LoadCredential=foo:/run/systemd-vaultd/sock --wait --pipe cat '${CREDENTIALS_DIRECTORY}/foo'
#systemd-vaultd: go run . -secrets tmp/secrets -sock tmp/sock
