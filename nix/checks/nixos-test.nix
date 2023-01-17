{ makeTest ? import <nixpkgs/nixos/tests/make-test-python.nix>
, pkgs ? (import <nixpkgs> { })
,
}:
let
  makeTest' = args:
    makeTest args {
      inherit pkgs;
      inherit (pkgs) system;
    };
in
{
  vault-agent = makeTest' (import ./vault-agent-test.nix);
  systemd-vaultd = makeTest' (import ./systemd-vaultd-test.nix);
  unittests = makeTest' {
    name = "unittests";
    nodes.server = {
      imports = [
        ../modules/systemd-vaultd.nix
      ];
    };

    testScript = ''
      start_all()
      server.succeed("machinectl shell .host ${pkgs.callPackage ./unittests.nix {}} >&2")
      # machinectl does not passthru exit codes, so we have to check manually
      server.succeed("[[ -f /tmp/success ]]")
    '';
  };
}
