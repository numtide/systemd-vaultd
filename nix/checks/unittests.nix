{
  writeShellScript,
  python3,
  pkgs,
  lib,
  coreutils,
  systemd
}: let
  systemd-vaultd = pkgs.callPackage ../../default.nix {};
in
  writeShellScript "unittests" ''
    set -eu -o pipefail
    export PATH=${lib.makeBinPath [ python3.pkgs.pytest coreutils systemd ]}
    export SYSTEMD_VAULTD_BIN=${systemd-vaultd}/bin/systemd-vaultd
    export TMPDIR=$(mktemp -d)
    trap 'rm -rf $TMPDIR' EXIT
    cp --no-preserve=mode --preserve=timestamps -r ${../..} "$TMPDIR/source"
    cd "$TMPDIR/source"
    pytest -s ./tests
    # we need this in our nixos tests
    touch /tmp/success
  ''
