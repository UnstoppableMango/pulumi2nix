# Runs `pulumi package gen-sdk` against a `schema.json`, for packages (like component
# providers) that don't ship a pre-generated `sdk/<lang>` tree upstream. `--out $out/sdk`
# (not `$out/sdk/${lang}`) is used because gen-sdk appends the language name itself,
# landing output at the `$out/sdk/<lang>` shape `lib/sdks/*.nix` expect.
#
# `schemaOverrides` patches the schema before codegen runs. A schema extracted from
# source by `mk-component-schema.nix` carries no per-language settings, and go's codegen
# needs `language.go.importBasePath` to emit self-imports matching the directory layout
# it writes - without it the SDK can't compile. See `lib/mk-generated-go-sdk.nix`, which
# also supplies the `go.mod`/`go.sum` gen-sdk never emits.
{
  lib,
  stdenv,
  jq,
  pulumi,
}:
{
  schema,
  lang,
  languagePlugin,
  pname,
  version,
  schemaOverrides ? { },
  meta ? { },
  ...
}:
stdenv.mkDerivation {
  name = "${pname}-generated-sdk-${lang}";
  inherit version meta;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [
    pulumi
    languagePlugin
  ]
  ++ lib.optional (schemaOverrides != { }) jq;

  installPhase = ''
    runHook preInstall

    export HOME=$TMPDIR
    schemaFile=${schema}/schema.json
    ${lib.optionalString (schemaOverrides != { }) ''
      jq --argjson overrides ${lib.escapeShellArg (builtins.toJSON schemaOverrides)} \
        '. * $overrides' "$schemaFile" > patched-schema.json
      schemaFile=patched-schema.json
    ''}
    pulumi package gen-sdk "$schemaFile" --language ${lang} --out $out/sdk

    runHook postInstall
  '';
}
