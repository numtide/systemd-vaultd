{
  description = "Description for the project";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs.follows = "nixpkgs";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
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
          nixosTests = (pkgs.callPackages ./nix/checks/nixos-test.nix {
            makeTest = import (pkgs.path + "/nixos/tests/make-test-python.nix");
            vaultAgentModule = self.nixosModules.vaultAgent;
          });
        in {
          treefmt = pkgs.callPackage ./nix/checks/treefmt.nix {};
          inherit (nixosTests) unittests vault-agent;
        };
      };
      flake.nixosModules = {
        vaultAgent = ./nix/modules/vault-agent.nix;
      };
    };
}
