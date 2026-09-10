# Builds a provider's `pulumi-resource-<name>` plugin binary out of the repo's
# `provider/` module, and nothing else: no schema generation, no SDKs.
#
# Providers differ in whether the binary carries the schema at all. A bridged
# provider embeds it, and its `cmd/<cmdRes>/generate.go` reads `schema.json`
# from the tree to write the version-stamped `schema-embed.json` that `main.go`
# embeds; pass `schema` (a `mkSchema` derivation) and the already-built
# `schema.json` is planted where that step expects it, instead of a second gen
# tool run rebuilding it in place. A `pulumi-go-provider` native provider serves
# its schema from Go structs at runtime and needs neither argument.
{
  lib,
  buildGoModule,
  fetchProviderSource,
  srcName,
}:
{
  version,
  cmdRes,
  src ? fetchProviderSource "mk-provider-plugin.nix" args,
  sourceRoot ? "${srcName src}/provider",

  # A schema derivation exposing `$out/schema.json`, planted at `schemaPath`
  # before the build. Null for providers whose binary does not embed one.
  schema ? null,
  schemaPath ? "provider/cmd/${cmdRes}/schema.json",

  # `go generate cmd/<cmdRes>/main.go`, which is what turns a planted
  # `schema.json` into the embedded `schema-embed.json`.
  goGenerate ? schema != null,

  extraLdflags ? [ ],
  ...
}@args:
let
  controlArgs = [
    "cmd"
    "cmdGen"
    "cmdRes"
    "repo"
    "owner"
    "rev"
    "hash"
    "fetchSubmodules"
    "extraLdflags"
    "schema"
    "schemaPath"
    "goGenerate"
    "sdks"
  ];

  plantSchema = lib.optionalString (schema != null) ''
    pushd ..
    schemaDir="$(dirname ${lib.escapeShellArg schemaPath})"
    mkdir -p "$schemaDir"
    chmod u+w "$schemaDir"
    cp ${schema}/schema.json ${lib.escapeShellArg schemaPath}
    chmod u+w ${lib.escapeShellArg schemaPath}
    popd
  '';

  generate = lib.optionalString goGenerate ''
    VERSION=v${version} go generate cmd/${cmdRes}/main.go
  '';

  postConfigure = lib.concatStringsSep "\n" (
    lib.filter (part: part != "") [
      plantSchema
      generate
      (args.postConfigure or "")
    ]
  );
in
buildGoModule (
  {
    pname = args.pname or args.repo;
    inherit sourceRoot;

    subPackages = [ "cmd/${cmdRes}" ];

    doCheck = false;

    ldflags = [
      "-s"
      "-w"
    ]
    ++ extraLdflags;
  }
  // removeAttrs args controlArgs
  // lib.optionalAttrs (postConfigure != "") { inherit postConfigure; }
)
