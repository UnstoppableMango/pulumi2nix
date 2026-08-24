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
