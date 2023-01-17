{ systemd
, fetchpatch
,
}:
systemd.overrideAttrs (old: {
  patches =
    old.patches
    ++ [
      (fetchpatch {
        url = "https://github.com/Mic92/systemd/commit/93a2921a81cab3be9b7eacab6b0095c96a0ae9e2.patch";
        sha256 = "sha256-7WlhMLE7sfD3Cxn6n6R1sUNzUOvas7XMyabi3bsq7jM=";
      })
    ];
})
