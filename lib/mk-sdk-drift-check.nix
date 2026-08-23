# Fails if a provider's committed `sdk/<lang>` no longer matches what its gen
# tool emits from the current source.
#
# The provider builders read SDK source straight out of the source tree's
# `sdk/<lang>` (see lib/with-sdks.nix), so a resource change that lands without
# a regenerated SDK still builds, and `nix flake check` stays green against a
# stale tree. This closes that loop: it re-runs the same `cmdGen` binary the
# provider build already uses, into a scratch directory, and diffs the result
# against what is committed.
#
# `pulumiGen` is the already-built gen tool rather than a rebuild, so the check
# shares the provider build's derivation instead of paying for a second Go build.
{
  lib,
  stdenv,
  diffutils,
  srcName,
}:
{
  pname,
  version,
  lang,
  src,
  cmdGen,
  pulumiGen,

  # Where the committed tree lives, relative to the source root. Only providers
  # that put their SDKs somewhere other than `sdk/<lang>` need this.
  sdkPath ? "sdk/${lang}",

  # Basenames `diff -r` skips, as a replaceable policy rather than a hardcoded
  # list. The default covers the files a tfgen binary never emits - they are
  # committed by hand, so they would always show up as drift. `extraExclude`
  # appends to whatever `exclude` ends up being.
  exclude ? [
    "package-lock.json"
    "go.mod"
    "go.sum"
    "version.txt"
  ],
  extraExclude ? [ ],

  meta ? { },
}:
let
  excluded = lib.unique (exclude ++ extraExclude);
  excludeFlags = lib.concatMapStringsSep " " (name: "--exclude=${lib.escapeShellArg name}") excluded;

  message = ''

    ${pname}: ${sdkPath} does not match what ${cmdGen} generates.

    The committed SDK is stale with respect to the provider source. Regenerate it
    with `${cmdGen} ${lang} --out ${sdkPath}` (usually via the repo's `make generate`)
    and commit the result.

    Excluded from the comparison: ${lib.concatStringsSep ", " excluded}
    In the diff below, "-" lines are the committed ${sdkPath} and "+" lines are
    what was just generated.
  '';
in
stdenv.mkDerivation {
  name = "${pname}-sdk-${lang}-generated";
  inherit src version meta;

  sourceRoot = srcName src;

  nativeBuildInputs = [
    pulumiGen
    diffutils
  ];

  dontConfigure = true;
  dontBuild = true;

  # Runs from the source root, which is where mkTerraformBridgeProvider's
  # `postConfigure` invokes the same binary.
  installPhase = ''
    runHook preInstall

    if [[ ! -d ${lib.escapeShellArg sdkPath} ]]; then
      echo "mkSdkDriftCheck: ${pname} has no committed ${sdkPath} to compare against." >&2
      echo "Either commit the generated SDK, or drop ${lang} from this provider's drift check." >&2
      exit 1
    fi

    generated="$NIX_BUILD_TOP/generated-${lang}"
    mkdir -p "$generated"
    ${cmdGen} ${lang} --out "$generated"

    if ! diff -r -u ${excludeFlags} ${lib.escapeShellArg sdkPath} "$generated" \
      > "$NIX_BUILD_TOP/drift.diff"; then
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
