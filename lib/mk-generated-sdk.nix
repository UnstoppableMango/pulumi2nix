# Runs `pulumi package gen-sdk` against a `schema.json`, for packages (like component
# providers) that don't ship a pre-generated `sdk/<lang>` tree upstream. `--out $out/sdk`
# (not `$out/sdk/${lang}`) is used because gen-sdk appends the language name itself,
# landing output at the `$out/sdk/<lang>` shape `lib/sdks/*.nix` expect.
#
# Verified network-free for nodejs/go/dotnet. Go's output lacks `go.mod`/`go.sum` and
# needs a separate fixup step before `lib/sdks/go.nix` can consume it.
{
  stdenv,
  pulumi,
}:
{
  schema,
  lang,
  languagePlugin,
  pname,
  version,
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
  ];

  installPhase = ''
    runHook preInstall

    export HOME=$TMPDIR
    pulumi package gen-sdk ${schema}/schema.json --language ${lang} --out $out/sdk

    runHook postInstall
  '';
}
