{
  lib,
  buildGoModule,
}:
buildGoModule {
  name = "systemd-vaultd";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./go.mod
      ./cmd
      (lib.fileset.fileFilter (file: file.hasExt "go") ./.)
    ];
  };
  vendorHash = null;
  meta = {
    description = "A proxy for secrets between systemd services and vault";
    homepage = "https://github.com/numtide/systemd-vaultd";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ mic92 ];
    platforms = lib.platforms.unix;
    mainProgram = "systemd-vaultd";
  };
}
