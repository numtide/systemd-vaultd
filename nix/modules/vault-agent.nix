{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.vault;
  settingsFormat = pkgs.formats.json { };

  autoAuthMethodModule = lib.types.submodule {
    freeformType = lib.types.attrsOf lib.types.unspecified;

    options = {
      type = lib.mkOption {
        type = lib.types.str;
      };

      config = lib.mkOption {
        type = lib.types.attrsOf lib.types.unspecified;
      };
    };
  };

  autoAuthModule = lib.types.submodule {
    freeformType = lib.types.attrsOf lib.types.unspecified;

    options = {
      method = lib.mkOption {
        type = lib.types.listOf autoAuthMethodModule;
        default = [ ];
      };
    };
  };

  templateConfigModule = lib.types.submodule {
    freeformType = lib.types.attrsOf lib.types.unspecified;

    options = {
      exit_on_retry_failure = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
    };
  };

  agentConfigType = lib.types.submodule {
    freeformType = lib.types.attrsOf lib.types.unspecified;

    options = {
      auto_auth = lib.mkOption {
        type = autoAuthModule;
        default = { };
      };

      template_config = lib.mkOption {
        type = templateConfigModule;
        default = { };
      };
    };
  };
in
{
  options.services.vault.agents = lib.mkOption {
    default = { };
    description = "Instances of vault agent";
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          package = lib.mkOption {
            description = "Vault-compatible agent package to use (defaults to OpenBao, since HashiCorp Vault is no longer free software)";
            type = lib.types.package;
            default = pkgs.openbao;
            defaultText = lib.literalExpression "pkgs.openbao";
          };
          settings = lib.mkOption {
            description = "agent configuration";
            type = agentConfigType;
          };
        };
      }
    );
  };
  config = {
    systemd.services = lib.mapAttrs' (
      name: instanceCfg:
      lib.nameValuePair "vault-agent-${name}" {
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];

        # Services that also have `stopIfChanged = false` might wait for secrets
        # while `vault-agent` is still stopped. This for example happens with nginx.service.

        stopIfChanged = false;
        # Needs getent in PATH
        path = [ pkgs.getent ];
        serviceConfig = {
          Restart = "on-failure";
          ExecStart = "${lib.getExe instanceCfg.package} agent -config=${settingsFormat.generate "agent.json" instanceCfg.settings}";
        };
      }
    ) cfg.agents;
  };
}
