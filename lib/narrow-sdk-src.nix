{ lib }:
let
  defaults = rec {
    nodejs = {
      dir = "sdk/nodejs";
      extra = [
        "README.md"
        "LICENSE"
      ];
    };

    yarnNodejs = nodejs;

    go = {
      dir = "sdk/go";
      extra = [
        "sdk/go.mod"
        "sdk/go.sum"
      ];
    };

    dotnet.dir = "sdk/dotnet";

    python.dir = "sdk/python";
  };
in
{
  optionNames = [
    "narrowSrc"
    "srcPaths"
  ];

  narrow =
    lang: src: langArgs:
    let
      spec = defaults.${lang} or null;

      paths = langArgs.srcPaths or (if spec == null then null else [ spec.dir ] ++ (spec.extra or [ ]));

      root =
        if builtins.isPath src then
          src
        else if !lib.isDerivation src && lib.isStringLike src then
          /. + (builtins.unsafeDiscardStringContext "${src}")
        else
          null;

      anchored = langArgs ? srcPaths || builtins.pathExists (root + "/${spec.dir}");

      narrowed = lib.fileset.toSource {
        inherit root;
        fileset = lib.fileset.unions (map (path: lib.fileset.maybeMissing (root + "/${path}")) paths);
      };
    in
    if
      !(langArgs.narrowSrc or true)
      || paths == null
      || root == null
      || !builtins.pathExists root
      || !anchored
    then
      src
    else
      narrowed;
}
