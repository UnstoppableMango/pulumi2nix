# Attaches a `{ <lang> = drv; }` set onto a base derivation's `passthru.sdks`.
# Shared by the two layerers so the chaining contract lives in one place: each
# one *overrides* onto whatever the derivation beneath it already carries
# rather than replacing it, letting mk-terraform-bridge-provider.nix stack
# with-sdks.nix and with-generated-sdks.nix on the same base. An empty set
# returns `base` untouched, so a provider that declares no SDKs pays no
# `overrideAttrs`.
_: base: extraSdks:
if extraSdks == { } then
  base
else
  base.overrideAttrs (old: {
    passthru = (old.passthru or { }) // {
      sdks = (old.passthru.sdks or { }) // extraSdks;
    };
  })
