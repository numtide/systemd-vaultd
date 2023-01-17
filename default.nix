{ pkgs ? import <nixpkgs> { } }:
pkgs.buildGoModule {
  name = "systemd-vaultd";
  src = ./.;
  vendorSha256 = null;
  meta = with pkgs.lib; {
    description = "A proxy for secrets between systemd services and vault";
    homepage = "https://github.com/numtide/systemd-vaultd";
    license = licenses.mit;
    maintainers = with maintainers; [ mic92 ];
    platforms = platforms.unix;
  };
}
