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
