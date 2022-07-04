{
  config,
  lib,
  pkgs,
  ...
}: let
  systemd-vaultd = pkgs.callPackage ../../default.nix {};
in {
  systemd.sockets.systemd-vaultd = {
    description = "systemd-vaultd socket";
    wantedBy = ["sockets.target"];

    socketConfig = {
      ListenStream = "/run/systemd-vaultd/sock";
      SocketUser = "root";
      SocketMode = "0600";
    };
  };
  systemd.services.systemd-vaultd = {
    description = "systemd-vaultd daemon";
    requires = ["systemd-vaultd.socket"];
    after = ["systemd-vaultd.socket"];
    # Restarting can break services waiting for secrets
    stopIfChanged = false;
    serviceConfig = {
      ExecStart = "${systemd-vaultd}/bin/systemd-vaultd";
    };
  };
}
