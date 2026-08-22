# Runs `pulumi package gen-sdk` against an already-produced `schema.json`
# (any `mk-schema.nix`-shaped derivation exposing `$out/schema.json`),
# using the given language's `pulumi-language-<lang>` plugin (nixpkgs'
# `pulumiPackages.pulumi-language-{go,nodejs,python}`, or this flake's own
# `pulumiLanguageDotnet` for dotnet). This is for packages that don't ship
# a pre-generated `sdk/<lang>` source tree the way `pulumi-command`/
# `pulumi-random` do (see `mk-schema.nix` + `postConfigure` in those
# examples) - namely component providers, whose SDK is generated on
# demand rather than checked in upstream.
#
# `pulumi package gen-sdk <schema.json> --language <lang> --out <dir>`
# writes to `<dir>/<lang>/...` itself (it appends the language name), so
# `--out $out/sdk` (not `$out/sdk/${lang}`) is what lands the output at
# the `$out/sdk/<lang>` shape `lib/sdks/*.nix` expect from their `src` -
# this derivation's `name` is set explicitly so `${src.name}/sdk/<lang>`
# interpolates the same way it would for a `fetchFromGitHub` source,
# letting those builders consume this output completely unmodified.
#
# Verified network-free inside a real sandboxed build for nodejs/go/dotnet
# via a real schema.json - `pulumi` finds the language plugin over PATH
# with no ambient network access. nodejs and dotnet output a complete,
# self-contained SDK source tree (package.json / .csproj included) that
# `lib/sdks/nodejs.nix`/`dotnet.nix` can build as-is. Go does not (no
# `go.mod`/`go.sum` in `gen-sdk`'s output) and needs a separate fixup step
# before `lib/sdks/go.nix` can consume it - not handled by this file.
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
