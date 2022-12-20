{
  description = "Description for the project";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    nixpkgs.url = "github:NixOS/nixpkgs";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux"];
      perSystem = {
        config,
        self',
        inputs',
        pkgs,
        system,
        ...
      }: {
        packages.default = pkgs.callPackage ./default.nix {};
        devShells.default = pkgs.callPackage ./shell.nix {};
        checks = let
          nixosTests = pkgs.callPackages ./nix/checks/nixos-test.nix {
            makeTest = import (pkgs.path + "/nixos/tests/make-test-python.nix");
          };
        in {
          treefmt = pkgs.callPackage ./nix/checks/treefmt.nix {};
          inherit (nixosTests) unittests vault-agent systemd-vaultd;
        };
      };
      flake.nixosModules = {
        vaultAgent = ./nix/modules/vault-agent.nix;
        systemdVaultd = ./nix/modules/systemd-vaultd.nix;
      };
    };
}
