# systemd-vaultd - load vault credentials with systemd units

> Mostly written in a train

- Jörg Thalheim

systemd-vaultd is a proxy between systemd and [vault agent](https://vaultproject.io).
It provides a unix socket that can be used in systemd services in the
`LoadCredential` option and then waits for vault agent to write these secrets in
json format at `/run/systemd-vaultd/<service_name>.service.json`.

This project's goal is to simplify the loading of [HashiCorp
Vault](https://www.vaultproject.io/) secrets from
[systemd](https://systemd.io/) units.

## Problem statement

Systemd has an option called `LoadCredentials` that allows to provide
credentials to a service:

```conf
# myservice.service
[Service]
ExecStart=/usr/bin/myservice.sh
LoadCredential=foobar:/etc/myfoobarcredential.txt
```

In this case systemd will load credential the file
`/etc/myfoobarcredential.txt` and provide it to the service at
`$CREDENTIAL_PATH/foobar`.

It's handy because it bypasses file permission issues.
/etc/myfoobarcredential.txt can be owned by root, and the unit run as a
different or dynamic user.

While vault agent also supports writing these secrets, a major issue is that
the consumer service may be started before vault agent was able to retrieve
secrets from vault. In that case, systemd would fail to start the service.

## The solution

In order to do so, I wrote a `systemd-vaultd` service which acts as a proxy
between systemd and vault agent that is running on the machine. It provides a
unix socket that can be used in systemd services in the `LoadCredential`
option and then waits for vault agent to write these secrets at
`/run/systemd-vaultd/<service_name>.json`.

We take advantage that in addition to normal paths, systemd also supports
loading credentials from unix sockets.

With `systemd-vaultd` the service `myservice.service` would look like this:

```conf
[Service]
ExecStart=/usr/bin/myservice.sh
LoadCredential=foobar:/run/systemd-vaultd/sock
```

vault agent is then expected to write secrets to `/run/systemd-vaultd/` in json format.

```
template {
  # this exposes all secrets in `secret/my-secret` to the service
  contents = "#{{ with secret \"secret/my-secret\" }}{{ .Data.data | toJSON }}{{ end }}"

  # an alternative is to expose only selected secrets like this:
  #  contents = <<EOF
  #  {{ with secret "secret/my-secret" }}{{ scratch.MapSet "secrets" "foobar" .Data.data.foo }}{{ end }}
  #  {{ scratch.Get "foobar" | explodeMap | toJSON }}
  #  EOF

  destination  = "/run/systemd-vaultd/secrets/myservice.service.json"
}
```

When `myservice` is started, systemd will open a connection to
`systemd-vaultd`'s socket. `systemd-vaultd` then either serve the secrets
from `/run/systemd-vaultd/secrets/myservice.service.json` or it waits with
inotify on secret directory for vault agent to write the secret.

Once the file `/run/systemd-vaultd/secrets/myservice.service.json` is present,
systemd-vaultd will parse it into a json map and lookup the keys specified in
`LoadCredential`.

⋈

## Installation

The installation requires a `go` compiler and `make` to be installed.

This command will install the `systemd-vaultd` binary to
`/usr/bin/systemd-vaultd` as well as installing a following systemd unit
files: `systemd-vaultd.service`, `systemd-vaultd.socket`:

```shell
make install
```

## Usage on NixOS

systemd-vaultd ships two NixOS modules as flake outputs:

- `nixosModules.systemdVaultd`: the systemd-vaultd socket/daemon plus a
  `systemd.services.<name>.vault` interface to declare secrets per service.
- `nixosModules.vaultAgent`: a small module to run one or more
  `vault agent` (OpenBao by default) instances via `services.vault.agents`.

### 1. Add the flake input and import the modules

```nix
{
  inputs.systemd-vaultd.url = "github:numtide/systemd-vaultd";

  outputs = { nixpkgs, systemd-vaultd, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        systemd-vaultd.nixosModules.systemdVaultd
        systemd-vaultd.nixosModules.vaultAgent
        ./configuration.nix
      ];
    };
  };
}
```

### 2. Configure a vault agent

The agent authenticates against your Vault/OpenBao server and renders the
secret templates. Any [vault agent configuration](https://developer.hashicorp.com/vault/docs/agent-and-proxy/agent)
can be passed via `settings`:

```nix
{
  services.vault.agents.default = {
    # package = pkgs.openbao; # default; set to pkgs.vault for HashiCorp Vault
    settings = {
      vault.address = "https://vault.example.com:8200";
      auto_auth.method = [
        {
          type = "approle";
          config = {
            role_id_file_path = "/var/lib/vault-agent/roleID";
            secret_id_file_path = "/var/lib/vault-agent/secretID";
            remove_secret_id_file_after_reading = false;
          };
        }
      ];
    };
  };
}
```

### 3. Declare secrets on your systemd services

Secrets are declared directly on the consuming service. systemd-vaultd wires
up `LoadCredential` for you and blocks service startup until the agent has
rendered the secret:

```nix
{
  systemd.services.myservice = {
    wantedBy = [ "multi-user.target" ];
    script = ''
      # secrets show up as systemd credentials
      cat "$CREDENTIALS_DIRECTORY/foo"
    '';

    vault = {
      # vault agent template rendering a JSON map; each key becomes a credential
      template = ''
        {{ with secret "secret/my-secret" }}{{ .Data.data | toJSON }}{{ end }}
      '';
      secrets.foo = { };
    };
  };
}
```

Binary secrets can be stored base64-encoded with a `base64:` prefix and are
decoded before being served, e.g.
`vault kv put secret/my-secret cert="base64:$(base64 < cert.der)"`.

### Environment variables instead of files

For services that expect secrets in environment variables, use
`environmentTemplate`:

```nix
{
  systemd.services.myservice = {
    script = ''
      echo "the secret is $SECRET_ENV"
    '';

    vault.environmentTemplate = ''
      {{ with secret "secret/my-secret" }}
      SECRET_ENV={{ .Data.data.foo }}
      {{ end }}
    '';
  };
}
```

### Reacting to secret changes

By default a service is reloaded (or restarted if it has no reload action)
when its secrets change (`vault.changeAction = "reload-or-restart"`). Set it
to `"restart"` or `"none"` to change that behavior.

Since systemd only reads `LoadCredential` at service start, reloading alone
does not refresh credentials. The bundled `systemd-vaultd-update-secrets`
helper can copy the rendered secrets into a directory owned by the service on
reload:

```nix
{
  systemd.services.myservice = {
    serviceConfig = {
      RuntimeDirectory = "myservice";
      ExecReload = "+${config.services.systemd-vaultd.package}/bin/systemd-vaultd-update-secrets /run/myservice/secrets";
    };
    preStart = ''
      cp -r "$CREDENTIALS_DIRECTORY" /run/myservice/secrets
    '';
  };
}
```

A complete end-to-end example (agent + secrets + reload handling) lives in
[nix/checks/systemd-vaultd-test.nix](nix/checks/systemd-vaultd-test.nix).

## Known limitations

systemd's LoadCredential option will not update credentials if a service is
reloaded. However systemd-vaultd called `systemd-vaultd-update-secrets` comes
with a helper program that can write secrets from the json file generated by
systemd-vaultd to a directory readable by the service. Checkout
`systemd-vaultd/nix/checks/systemd-vaultd-test.nix` for more details.

## License

Copyright (c) 2022 [Jörg Thalheim](https://github.com/mic92) and contributors.

This project is free software, and may be redistributed under the terms
specified in the [LICENSE](LICENSE) file.

## About

This project is maintained by Numtide.

Need help or support? [Contact us](https://numtide.com/contact)
