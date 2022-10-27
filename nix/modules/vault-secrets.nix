{
  lib,
  config,
  pkgs,
  ...
}: let
  secretType = serviceName:
    lib.types.submodule ({config, ...}: {
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

  getTemplate = serviceName: vaultConfig:
    {
      contents = vaultConfig.template;
      destination = "/run/systemd-vaultd/secrets/${serviceName}.service.json";
      perms = "0400";
    }
    // lib.optionalAttrs (vaultConfig.changeAction != null) {
      command = "systemctl ${
        if vaultConfig.changeAction == "restart"
        then "try-restart"
        else "try-reload-or-restart"
      } ${lib.escapeShellArg "${serviceName}.service"}";
    };

  vaultTemplates = config:
    lib.mapAttrsToList
    (serviceName: service:
      getTemplate serviceName services.${serviceName}.vault)
    (lib.filterAttrs (n: v: v.vault.secrets != {} && v.vault.agent == config._module.args.name) services);
in {
  options = {
    systemd.services = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({config, ...}: {
        options.vault = {
          changeAction = lib.mkOption {
            description = "What to do if any secrets in the environment change.";
            type = lib.types.nullOr (lib.types.enum [
              "none"
              "reload-or-restart"
              "restart"
            ]);
            default = "reload-or-restart";
          };

          template = lib.mkOption {
            type = lib.types.str;
            description = ''
              The vault agent template to use for this secret
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
            type = lib.types.attrsOf (secretType config._module.args.name);
            default = {};
            description = "List of secrets to load from vault agent template";
            example = {
              some-secret.template = ''{{ with secret "secret/some-secret" }}{{ .Data.data.some-key }}{{ end }}'';
            };
          };
        };
        config.serviceConfig.LoadCredential = lib.mapAttrsToList (_: config: "${config.name}:/run/systemd-vaultd/sock") config.vault.secrets;
      }));
    };

    services.vault.agents = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({config, ...}: {
        config.settings.template = vaultTemplates config;
      }));
    };
  };
}
