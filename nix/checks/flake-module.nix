{inputs, ...}: {
  imports = [
    inputs.treefmt-nix.flakeModule
  ];
  perSystem = {
    self',
    inputs',
    pkgs,
    system,
    ...
  }: {
    treefmt = {
      # Used to find the project root
      projectRootFile = "flake.lock";

      programs.gofumpt.enable = true;
      programs.prettier.enable = true;

      settings.formatter = {
        nix = {
          command = "sh";
          options = [
            "-eucx"
            ''
              # First deadnix
              ${pkgs.lib.getExe pkgs.deadnix} --edit "$@"
              # Then nixpkgs-fmt
              ${pkgs.lib.getExe pkgs.nixpkgs-fmt} "$@"
            ''
            "--"
          ];
          includes = ["*.nix"];
        };

        python = {
          command = "sh";
          options = [
            "-eucx"
            ''
              ${pkgs.lib.getExe pkgs.ruff} --fix "$@"
              ${pkgs.lib.getExe pkgs.python3.pkgs.black} "$@"
            ''
            "--" # this argument is ignored by bash
          ];
          includes = ["*.py"];
        };
      };

      checks =
        let
          nixosTests = pkgs.callPackages ./nixos-test.nix {
            makeTest = import (pkgs.path + "/nixos/tests/make-test-python.nix");
          };
        in
        {
          inherit (nixosTests) unittests vault-agent systemd-vaultd;
        };
    };

    checks = let
      nixosTests = pkgs.callPackages ./nix/checks/nixos-test.nix {
        makeTest = import (pkgs.path + "/nixos/tests/make-test-python.nix");
      };
    in {
      inherit (nixosTests) unittests vault-agent systemd-vaultd;
    };
  };
}
