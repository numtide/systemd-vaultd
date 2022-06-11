{pkgs ? import <nixpkgs> {}}:
with pkgs;
  mkShellNoCC {
    buildInputs = [
      python3.pkgs.pytest
      python3.pkgs.flake8
      python3.pkgs.black
      python3.pkgs.mypy

      gofumpt
      golangci-lint
      alejandra
      vault
      systemd
      hivemind
      go
      treefmt
    ];
  }
