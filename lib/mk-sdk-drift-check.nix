# Fails when a provider's committed `sdk/<lang>` doesn't match what the same
# provider generates. Provider builders read SDK source straight out of the
# tree's `sdk/<lang>`, so a resource change that lands without a regenerated SDK
# still builds and `nix flake check` stays green against a stale tree; this
# closes that loop.
#
# It generates nothing itself. Both sides are `mkSdkSource` derivations, so the
# check is a diff and the choice of generator stays with the caller: the gen
# tool (exact, replays tfgen's language overlays) or `gen-sdk` from the schema.
{
  lib,
  stdenv,
  diffutils,
}:
{
  pname,
  lang,

  # Both sides are SDK source trees, holding the SDK at `<path>` below.
  committed,
  against,
  committedPath ? "sdk/${lang}",
  againstPath ? "sdk/${lang}",

  # Names the command that regenerates the committed tree, for the failure
  # message only.
  regenerateCommand ? "the repo's `make generate`",

  exclude ? [
    "package-lock.json"
    "go.mod"
    "go.sum"
    "version.txt"
  ],
  extraExclude ? [ ],

  version ? "0",
  meta ? { },
}:
let
  excluded = lib.unique (exclude ++ extraExclude);
  excludeFlags = lib.concatMapStringsSep " " (name: "--exclude=${lib.escapeShellArg name}") excluded;

  message = ''

    ${pname}: ${committedPath} does not match what this provider generates.

    The committed SDK is stale with respect to the provider source. Regenerate it
    with ${regenerateCommand} and commit the result.

    Excluded from the comparison: ${lib.concatStringsSep ", " excluded}
    In the diff below, "-" lines are the committed ${committedPath} and "+" lines are
    what was just generated.
  '';
in
stdenv.mkDerivation {
  name = "${pname}-sdk-${lang}-drift";
  inherit version meta;

  nativeBuildInputs = [ diffutils ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    committed=${committed}/${committedPath}
    generated=${against}/${againstPath}

    if [[ ! -d "$committed" ]]; then
      echo "mkSdkDriftCheck: ${pname} has no committed ${committedPath} to compare against." >&2
      echo "Either commit the generated SDK, or drop ${lang} from this provider's drift check." >&2
      exit 1
    fi

    if ! diff -r -u ${excludeFlags} "$committed" "$generated" > "$NIX_BUILD_TOP/drift.diff"; then
      printf '%s\n' ${lib.escapeShellArg message} >&2
      cat "$NIX_BUILD_TOP/drift.diff" >&2
      exit 1
    fi

    touch $out

    runHook postInstall
  '';

  passthru = {
    inherit lang;
    exclude = excluded;
  };
}
