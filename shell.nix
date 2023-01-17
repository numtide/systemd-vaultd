{ pkgs ? import <nixpkgs> { } }:
with pkgs;
mkShellNoCC {
  buildInputs = [
    python3.pkgs.pytest
    python3.pkgs.mypy

    golangci-lint
    vault
    systemd
    hivemind
    go
    just
  ];
}
