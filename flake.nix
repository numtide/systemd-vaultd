{
  description = "Description for the project";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" ];
      imports = [
        ./nix/checks/flake-module.nix
      ];
      perSystem =
        { config
        , pkgs
        , ...
        }: {
          packages.default = pkgs.callPackage ./default.nix { };
          packages.systemd = pkgs.callPackage ./nix/pkgs/systemd.nix { };
          devShells.default = pkgs.mkShellNoCC {
            buildInputs = with pkgs; [
              python3.pkgs.pytest
              python3.pkgs.mypy

              golangci-lint
              vault
              systemd
              hivemind
              go
              just
              config.packages.treefmt
              config.packages.systemd
            ];
          };

        };
      flake.nixosModules = {
        vaultAgent = ./nix/modules/vault-agent.nix;
        systemdVaultd = ./nix/modules/systemd-vaultd.nix;
      };
    };
}
