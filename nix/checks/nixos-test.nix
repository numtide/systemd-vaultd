{
  makeTest ? import <nixpkgs/nixos/tests/make-test-python.nix>,
  pkgs ? (import <nixpkgs> {}),
}: let
  makeTest' = args:
    makeTest args {
      inherit pkgs;
      inherit (pkgs) system;
    };
in {
  ssh-keys = makeTest' {
    name = "unitests";
    nodes.server = {pkgs, ...}: {
      # Important to get the systemd service running for root
      #environment.variables.XDG_RUNTIME_DIR = "/run/user/0";
    };

    testScript = ''
      start_all()
      server.succeed("machinectl shell .host ${pkgs.callPackage ./unittests.nix {}} >&2")
      # machinectl does not passthru exit codes, so we have to check manually
      server.succeed("[[ -f /tmp/success ]]")
    '';
  };
}
