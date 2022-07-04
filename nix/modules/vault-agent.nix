{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.vault;
  settingsFormat = pkgs.formats.json {};

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
        default = [];
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
        default = {};
      };

      template_config = lib.mkOption {
        type = templateConfigModule;
        default = {};
      };
    };
  };
in {
  options.services.vault.agents = lib.mkOption {
    default = {};
    description = "Instances of vault agent";
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        settings = lib.mkOption {
          description = "agent configuration";
          type = agentConfigType;
        };
      };
    });
  };
  config = {
    systemd.services = lib.mapAttrs' (name: instanceCfg:
      lib.nameValuePair "vault-agent-${name}" {
        after = ["network.target"];
        wantedBy = ["multi-user.target"];
        # Needs getent in PATH
        path = [pkgs.glibc];
        serviceConfig = {
          Restart = "on-failure";
          ExecStart = "${pkgs.vault}/bin/vault agent -config=${settingsFormat.generate "agent.json" instanceCfg.settings}";
        };
      })
    cfg.agents;
  };
}
