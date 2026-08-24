# Fails when a provider's committed `sdk/<lang>` doesn't match what its gen
# tool emits from source. Provider builders read SDK source straight out of
# the source tree's `sdk/<lang>` (see lib/with-sdks.nix), so a resource change
# that lands without a regenerated SDK still builds, and `nix flake check`
# stays green against a stale tree; this closes that loop by re-running the
# same `cmdGen` binary the provider build already uses into a scratch
# directory and diffing the result against what is committed.
#
{
  lib,
  stdenv,
  diffutils,
  pulumi,
  srcName,
}:
{
  pname,
  version,
  lang,
  src,
  cmdGen,
  pulumiGen,

  languagePlugin ? null,

  sdkPath ? "sdk/${lang}",

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
  ]
  ++ lib.optionals (languagePlugin != null) [
    pulumi
    languagePlugin
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    if [[ ! -d ${lib.escapeShellArg sdkPath} ]]; then
      echo "mkSdkDriftCheck: ${pname} has no committed ${sdkPath} to compare against." >&2
      echo "Either commit the generated SDK, or drop ${lang} from this provider's drift check." >&2
      exit 1
    fi

    generated="$NIX_BUILD_TOP/generated-${lang}"
    mkdir -p "$generated"

    export HOME=$TMPDIR
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
