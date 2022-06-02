with import <nixpkgs> {};
mkShell {
  nativeBuildInputs = [
    go
    vault
    python3.pkgs.pytest
  ];
}
