{ lib
, config
, pkgs
, ...
}:
let
  secretType = serviceName:
    lib.types.submodule ({ config, ... }: {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          default = config._module.args.name;
          description = ''
            Name of the secret used in LoadCredential
          '';
        };
        path = lib.mkOption {
          type = lib.types.str;
          default = "/run/credentials/${serviceName}.service/${config.name}";
          defaultText = "/run/credentials/$service.service/$name";
          description = ''
            Absolute path to systemd's loaded credentials.
            WARNING: Using this path might break if systemd in future decides to use
            a different location but /run/credentials
          '';
        };
      };
    });

  services = config.systemd.services;

  templateExec = serviceName: vaultConfig: { } //
    lib.optionalAttrs (vaultConfig.changeAction != null && vaultConfig.changeAction != "none") {
      exec = [
        ({
          command = "systemctl ${
        if vaultConfig.changeAction == "restart"
        then "try-restart"
        else "try-reload-or-restart"
      } ${lib.escapeShellArg "${serviceName}.service"}";
        } // lib.optionalAttrs
          (vaultConfig.command_timeout != null)
          { timeout = vaultConfig.command_timeout; })
      ];
    };

  getSecretTemplate = serviceName: vaultConfig:
    {
      contents = vaultConfig.template;
      destination = "/run/systemd-vaultd/secrets/${serviceName}.service.json";
      perms = "0400";
    }
    // templateExec serviceName vaultConfig;

  getEnvironmentTemplate = serviceName: vaultConfig:
    {
      contents = vaultConfig.environmentTemplate;
      destination = "/run/systemd-vaultd/secrets/${serviceName}.service.EnvironmentFile";
      perms = "0400";
    }
    // templateExec serviceName vaultConfig;

  vaultTemplates = config:
    (lib.mapAttrsToList
      (serviceName: _service:
        getSecretTemplate serviceName services.${serviceName}.vault)
      (lib.filterAttrs (_n: v: v.vault.template != null && v.vault.agent == config._module.args.name) services))
    ++ (lib.mapAttrsToList
      (serviceName: _service:
        getEnvironmentTemplate serviceName services.${serviceName}.vault)
      (lib.filterAttrs (_n: v: v.vault.environmentTemplate != null && v.vault.agent == config._module.args.name) services));
in
{
  options = {
    systemd.services = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ config, ... }:
        let
          serviceName = config._module.args.name;
        in
        {
          options.vault = {
            changeAction = lib.mkOption {
              description = ''
                What to do with the service if any secrets change
              '';
              type = lib.types.nullOr (lib.types.enum [
                "none"
                "reload-or-restart"
                "restart"
              ]);
              default = "reload-or-restart";
            };

            template = lib.mkOption {
              type = lib.types.nullOr lib.types.lines;
              default = null;
              description = ''
                The vault agent template to use for secrets
              '';
            };

            environmentTemplate = lib.mkOption {
              type = lib.types.nullOr lib.types.lines;
              default = null;
              description = ''
                The vault agent template to use for environment file
              '';
            };

            agent = lib.mkOption {
              type = lib.types.str;
              default = "default";
              description = ''
                Agent instance to use for this service
              '';
            };

            secrets = lib.mkOption {
              type = lib.types.attrsOf (secretType serviceName);
              default = { };
              description = "List of secrets to load from vault agent template";
              example = {
                some-secret.template = ''{{ with secret "secret/some-secret" }}{{ .Data.data.some-key }}{{ end }}'';
              };
            };

            command_timeout = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Maximum amount of time to wait for the optional command to return.
              '';
            };

          };
          config =
            let
              mkIfHasEnv = lib.mkIf (config.vault.environmentTemplate != null);
              mkIfHasSecret = lib.mkIf (config.vault.template != null);
            in
            {
              after = mkIfHasEnv [ "${serviceName}-envfile.service" ];
              bindsTo = mkIfHasEnv [ "${serviceName}-envfile.service" ];

              serviceConfig = {
                LoadCredential = mkIfHasSecret (lib.mapAttrsToList (_: config: "${config.name}:/run/systemd-vaultd/sock") config.vault.secrets);
                EnvironmentFile = mkIfHasEnv [ "/run/systemd-vaultd/secrets/${serviceName}.service.EnvironmentFile" ];
              };
            };
        }));
    };

    services.vault.agents = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ config, ... }: {
        config.settings.template = vaultTemplates config;
      }));
    };
  };

  config = {
    # we cannot use `systemd.services` here since this would create infinite recursion
    systemd.packages =
      let
        servicesWithEnv = builtins.attrNames (lib.filterAttrs (_n: v: v.vault.environmentTemplate != null) services);
      in
      [
        (pkgs.runCommand "env-services" { }
          (''
            mkdir -p $out/lib/systemd/system
          ''
          + (lib.concatMapStringsSep "\n"
            (service: ''
              cat > $out/lib/systemd/system/${service}-envfile.service <<EOF
              [Unit]
              Before=${service}.service
              BindsTo=${service}.service
              StopPropagatedFrom=${service}.service

              [Service]
              Type=oneshot
              ExecStart=${pkgs.coreutils}/bin/true
              RemainAfterExit=true
              LoadCredential=${service}.service.EnvironmentFile:/run/systemd-vaultd/sock

              [Install]
              WantedBy=${service}.service
              EOF
            '')
            servicesWithEnv)))
      ];
  };
}
