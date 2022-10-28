{
  description = "Description for the project";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs.follows = "nixpkgs";
    # https://github.com/NixOS/nixpkgs/pull/180114
    nixpkgs.url = "github:Mic92/nixpkgs/vault";
  };

  outputs = {
    self,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit self;} {
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
