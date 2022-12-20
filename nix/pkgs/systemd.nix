{
  systemd,
  fetchpatch,
}:
systemd.overrideAttrs (old: {
  patches =
    old.patches
    ++ [
      (fetchpatch {
        url = "https://github.com/Mic92/systemd/commit/93a2921a81cab3be9b7eacab6b0095c96a0ae9e2.patch";
        sha256 = "sha256-7WlhMLE7sfD3Cxn6n6R1sUNzUOvas7XMyabi3bsq7jM=";
      })
      # included in next release: https://github.com/systemd/systemd/pull/25721
      (fetchpatch {
        url = "https://github.com/systemd/systemd/commit/39ed2f02d0a00505fce34ce4281cc6e4f016ec6b.patch";
        sha256 = "sha256-RD8GhOxzNNgC0KKThRaeF2uP8Y+Tt7kVSDtf1ukUwcI=";
      })
    ];
})
