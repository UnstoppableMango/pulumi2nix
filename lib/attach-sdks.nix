_: base: extraSdks:
if extraSdks == { } then
  base
else
  base.overrideAttrs (old: {
    passthru = (old.passthru or { }) // {
      sdks = (old.passthru.sdks or { }) // extraSdks;
    };
  })
