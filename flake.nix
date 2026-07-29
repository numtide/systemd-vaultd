{
  description = "A proxy for secrets between systemd services and vault";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable-small";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      eachSystem = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      treefmtEval = eachSystem (pkgs: treefmt-nix.lib.evalModule pkgs ./nix/treefmt.nix);
    in
    {
      packages = eachSystem (pkgs: {
        default = pkgs.callPackage ./default.nix { };
      });

      formatter = eachSystem (pkgs: treefmtEval.${pkgs.stdenv.hostPlatform.system}.config.build.wrapper);

      checks = eachSystem (
        pkgs:
        let
          nixosTests = pkgs.callPackages ./nix/checks/nixos-test.nix {
            makeTest = import (pkgs.path + "/nixos/tests/make-test-python.nix");
          };
        in
        {
          inherit (nixosTests) unittests vault-agent systemd-vaultd;
          treefmt = treefmtEval.${pkgs.stdenv.hostPlatform.system}.config.build.check self;
        }
      );

      devShells = eachSystem (pkgs: {
        default = pkgs.mkShellNoCC {
          buildInputs = with pkgs; [
            python3.pkgs.pytest
            python3.pkgs.mypy

            golangci-lint
            openbao
            systemd
            hivemind
            go
            just
            treefmtEval.${pkgs.stdenv.hostPlatform.system}.config.build.wrapper
          ];
        };
      });

      nixosModules = {
        vaultAgent = ./nix/modules/vault-agent.nix;
        systemdVaultd = ./nix/modules/systemd-vaultd.nix;
      };
    };
}
