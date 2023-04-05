{ pkgs
, lib
, config
, ...
}:
let
  systemd-vaultd = pkgs.callPackage ../../default.nix { };
in
{
  imports = [
    ./vault-secrets.nix
  ];
  options = {
    services.systemd-vaultd = {
      package = lib.mkOption {
        type = lib.types.package;
        default = systemd-vaultd;
        defaultText = "pkgs.systemd-vaultd";
        description = ''
          The package to use for systemd-vaultd
        '';
      };
    };
  };

  config = {
    systemd.sockets.systemd-vaultd = {
      description = "systemd-vaultd socket";
      wantedBy = [ "sockets.target" ];

      socketConfig = {
        ListenStream = "/run/systemd-vaultd/sock";
        SocketUser = "root";
        SocketMode = "0600";
      };
    };
    systemd.services.systemd-vaultd = {
      description = "systemd-vaultd daemon";
      requires = [ "systemd-vaultd.socket" ];
      after = [ "systemd-vaultd.socket" ];
      # Restarting can break services waiting for secrets
      stopIfChanged = false;
      serviceConfig = {
        ExecStart = "${config.services.systemd-vaultd.package}/bin/systemd-vaultd";
      };
    };
  };
}
