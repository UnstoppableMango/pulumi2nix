# Fails when a provider's committed `sdk/<lang>` doesn't match what its gen
# tool emits from source. Provider builders read SDK source straight out of
# the source tree's `sdk/<lang>` (see lib/with-sdks.nix), so a resource change
# that lands without a regenerated SDK still builds, and `nix flake check`
# stays green against a stale tree; this closes that loop by re-running the
# same `cmdGen` binary the provider build already uses into a scratch
# directory and diffing the result against what is committed.
#
# `pulumiGen` is the already-built gen tool, so the check shares the provider
# build's derivation instead of paying for a second Go build.
#
# On a bridge whose `emitSDK` routes Golang, NodeJS, Python and CSharp through
# `runPulumiPackageGenSDK` (an `exec.Command("pulumi", "package", "gen-sdk",
# "--language", <lang>, ...)`), the gen tool is a schema producer and a
# subprocess launcher, so the check also needs the `pulumi` CLI plus that
# language's host on PATH or it dies with `exec: "pulumi": executable file not
# found in $PATH`. Whether a given provider's bridge delegates that way is not
# detectable from this file - it depends on the bridge version in the
# provider's own go.mod, unreadable at eval time - so `languagePlugin` is the
# caller's explicit declaration that it does: passing it adds both tools,
# omitting it keeps the closure-free shape.
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

  # The `pulumi-language-<lang>` host `pulumi package gen-sdk` shells out to,
  # e.g. `pkgs.pulumiPackages.pulumi-nodejs`; .NET has no nixpkgs build, so use
  # this repo's `pulumiLanguageDotnet`. Required on a delegating bridge, and
  # left `null` otherwise: a check whose gen tool never spawns `pulumi` should
  # not drag the CLI's closure in to satisfy a PATH lookup it will not make.
  languagePlugin ? null,

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
  ]
  ++ lib.optionals (languagePlugin != null) [
    pulumi
    languagePlugin
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

    # A delegating bridge runs the `pulumi` CLI, which insists on a writable
    # home for its plugin cache and credentials file. Same reason
    # lib/mk-generated-sdk.nix sets it; harmless when the gen tool codegens
    # in-process and never looks.
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
