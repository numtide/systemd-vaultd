{
  runCommandNoCC,
  gofumpt,
  alejandra,
  python3,
  treefmt,
}:
runCommandNoCC "treefmt" {
  nativeBuildInputs = [
    gofumpt
    treefmt
    alejandra
    python3.pkgs.flake8
    python3.pkgs.black
  ];
} ''
  # keep timestamps so that treefmt is able to detect mtime changes
  cp --no-preserve=mode --preserve=timestamps -r ${../..} source
  cd source
  HOME=$TMPDIR treefmt --no-cache --fail-on-change
  touch $out
''
