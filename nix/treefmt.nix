{ ... }:
{
  # Used to find the project root
  projectRootFile = "flake.lock";

  programs.gofumpt.enable = true;
  programs.prettier.enable = true;

  programs.deadnix.enable = true;
  programs.nixfmt.enable = true;

  programs.ruff-check.enable = true;
  programs.ruff-format.enable = true;
}
