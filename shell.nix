{ pkgs ? import <nixpkgs> {} }:

with pkgs;

mkShell {
  buildInputs = [
    python3.pkgs.pytest
    golangci-lint
    vault
    systemd
    hivemind
    go
  ];
}
