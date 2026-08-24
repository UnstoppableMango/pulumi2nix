# Builds one language's SDK *source tree*, the artifact sitting between
# `schema.json` and a packaged SDK.
#
# Pulumi produces that tree three ways, and this builder takes all three as
# producer arguments rather than splitting into three builders:
#
#   src      the upstream repo's committed `sdk/<lang>`, narrowed to the
#            subtree that language builds from
#   schema   `pulumi package gen-sdk`, the schema-descended route
#   genTool  `<cmdGen> <lang> --out`, the provider's own tfgen emitting an SDK
#            directly. Unlike gen-sdk this replays tfgen's per-language
#            overlays, which is why the drift check compares against it.
#
# Whichever producer runs, the output holds the SDK at `sdk/<lang>`, which is
# the layout every builder in `lib/sdks` already expects.
{
  lib,
  stdenv,
  jq,
  pulumi,
  narrowSdkSrc,
  srcName,
}:
{
  lang,
  pname,
  version,
  meta ? { },

  # Producers. Exactly one of `schema` / `genTool`, or neither for a committed
  # tree. `genTool` additionally needs `src`, the repo it runs in.
  src ? null,
  schema ? null,
  genTool ? null,

  # The `pulumi-language-<lang>` host. Required by the schema producer, and by
  # the genTool producer on a bridge whose tfgen shells out to gen-sdk.
  languagePlugin ? null,

  # Merged into the schema before codegen, which is how per-language settings
  # (notably go's `importBasePath`) reach a schema extracted from source.
  schemaOverrides ? { },

  # `gen-sdk --language go` emits no module files, so a generated go tree is
  # completed with a caller-supplied pair.
  goMod ? null,
  goSum ? null,

  narrowSrc ? true,
  srcPaths ? null,
  ...
}:
let
  producers = lib.filter (p: p.set) [
    {
      name = "schema";
      set = schema != null;
    }
    {
      name = "genTool";
      set = genTool != null;
    }
  ];

  requireOneProducer = lib.throwIf (lib.length producers > 1) ''
    mkSdkSource: ${pname} ${lang} sets ${lib.concatMapStringsSep " and " (p: "`${p.name}`") producers},
    which are alternative producers of the same SDK source tree. Pass `schema` to
    codegen it with `pulumi package gen-sdk`, or `genTool` to have the provider's
    own gen tool emit it, not both.
  '';

  requireSrc = lib.throwIf (src == null) ''
    mkSdkSource: ${pname} ${lang} needs a `src`. Without `schema` or `genTool`
    the source is the upstream repo's committed `sdk/${lang}`, so there has to be
    a repo to read it out of.
  '';

  requireGenToolSrc = lib.throwIf (genTool != null && src == null) ''
    mkSdkSource: ${pname} ${lang} passes `genTool` without a `src`. The gen tool
    runs at the repo root, the same way the provider's own `make generate` does,
    so it needs the tree it is generating against.
  '';

  requirePlugin = lib.throwIf (schema != null && languagePlugin == null) ''
    mkSdkSource: ${pname} ${lang} generates from a schema without a `languagePlugin`.

    Generating an SDK runs `pulumi package gen-sdk --language ${lang}`, which needs that
    language's own host binary on PATH: `pkgs.pulumiPackages.pulumi-{nodejs,python,go}`,
    or this repo's `pulumiLanguageDotnet` for .NET, which nixpkgs has no build for.
    Set `<lang>Args.languagePlugin` (`sdks.${lang}.languagePlugin` in the flake module),
    or drop `generate` to keep building the repo's committed `sdk/${lang}`.
  '';

  committed = narrowSdkSrc.narrow lang src (
    { inherit narrowSrc; } // lib.optionalAttrs (srcPaths != null) { inherit srcPaths; }
  );

  patchSchema = lib.optionalString (schemaOverrides != { }) ''
    jq --argjson overrides ${lib.escapeShellArg (builtins.toJSON schemaOverrides)} \
      '. * $overrides' "$schemaFile" > patched-schema.json
    schemaFile=patched-schema.json
  '';

  completeGoModule = lib.optionalString (goMod != null) ''
    cp ${goMod} $out/sdk/go.mod
    ${lib.optionalString (goSum != null) "cp ${goSum} $out/sdk/go.sum"}
  '';

  generated = stdenv.mkDerivation {
    name = "${pname}-sdk-src-${lang}";
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
      ${patchSchema}
      pulumi package gen-sdk "$schemaFile" --language ${lang} --out $out/sdk
      ${completeGoModule}

      runHook postInstall
    '';
  };

  fromGenTool = stdenv.mkDerivation {
    name = "${pname}-sdk-src-${lang}";
    inherit src version meta;

    sourceRoot = srcName src;

    nativeBuildInputs = [
      genTool
    ]
    ++ lib.optionals (languagePlugin != null) [
      pulumi
      languagePlugin
    ];

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      export HOME=$TMPDIR
      mkdir -p $out/sdk/${lang}
      ${lib.getExe genTool} ${lang} --out $out/sdk/${lang}

      runHook postInstall
    '';
  };
in
requireOneProducer (
  requirePlugin (
    requireGenToolSrc (
      if schema != null then
        generated
      else if genTool != null then
        fromGenTool
      else
        requireSrc committed
    )
  )
)
