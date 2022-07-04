# run with `hivemind``
systemd-service: sleep 3 && systemd-run --user --collect -u vault-nixos3.service -p LoadCredential=foo:$(pwd)/tmp/sock --wait --pipe cat '${CREDENTIALS_DIRECTORY}/foo'
vault: vault server -dev -dev-root-token-id secret
vault-agent:  sleep 5 && ./tests/setup-vault && vault agent -config ./tests/vault-agent-example.hcl
systemd-vaultd: go run . -secrets tmp/secrets -sock tmp/sock
