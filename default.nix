with import <nixpkgs> {};

buildGoModule {
  name = "systemd-vault";
  src = ./.;
  vendorSha256 = null;
  checkInputs = [
    python3.pkgs.pytest
    golangci-lint
    vault
  ];
  meta = with lib; {
    description = "A proxy for secrets between systemd services and vault";
    homepage = "https://github.com/numtide/systemd-vault";
    license = licenses.mit;
    maintainers = with maintainers; [ mic92 ];
    platforms = platforms.unix;
  };
}
#mkShell {
#  nativeBuildInputs = [
#    go
#    hivemind
#  ];
#}
