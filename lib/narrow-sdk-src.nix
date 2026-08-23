# Narrows a provider repo's `src` down to the subtree one language's SDK build
# actually reads, so an unrelated file change no longer moves that SDK's input
# hash. The builders already select the subtree with `sourceRoot`, but that is a
# build-time choice: without this the README, the CI config and every other file
# in the repo are inputs to all four SDK derivations, and editing any of them
# rebuilds every one of them.
#
# Only a tree readable at eval time can be narrowed: a path, or a realized store
# path such as a flake input or `inputs.self`. A `src` that is still an unbuilt
# derivation - the default `fetchFromGitHub` fetch - is returned unchanged:
# `lib.fileset` cannot look inside one without building it first, and narrowing
# would buy nothing there anyway, since a fetch's output only moves when `rev`
# does. That makes this a no-op for the common `owner`/`repo`/`rev`/`hash` path
# and a real saving for the local-checkout workflow it was written for.
{ lib }:
let
  # Repo-relative paths each language's SDK build reads. `dir` is the one
  # `sourceRoot` points at; `extra` are the files the build reaches for outside
  # it - lib/sdks/npm.nix copies `../../README.md ../../LICENSE` in `postBuild`,
  # and a Pulumi go SDK's module root is `sdk/go.mod`, one level above `sdk/go`.
  defaults = {
    nodejs = {
      dir = "sdk/nodejs";
      extra = [
        "README.md"
        "LICENSE"
      ];
    };

    yarnNodejs = {
      dir = "sdk/nodejs";
      extra = [
        "README.md"
        "LICENSE"
      ];
    };

    go = {
      dir = "sdk/go";
      extra = [
        "sdk/go.mod"
        "sdk/go.sum"
      ];
    };

    dotnet = {
      dir = "sdk/dotnet";
      extra = [ ];
    };

    python = {
      dir = "sdk/python";
      extra = [ ];
    };
  };
in
{
  # Consumed here rather than by a builder, so call sites strip them from the
  # per-language args before the rest reaches buildNpmPackage and friends.
  optionNames = [
    "narrowSrc"
    "srcPaths"
  ];

  # `langArgs` is the language's own args attrset; only `narrowSrc` (opt out,
  # keeping the whole tree) and `srcPaths` (replace the default path list) are
  # read from it, both optional.
  narrow =
    lang: src: langArgs:
    let
      spec = defaults.${lang} or null;

      paths = langArgs.srcPaths or (if spec == null then null else [ spec.dir ] ++ spec.extra);

      root =
        if builtins.isPath src then
          src
        # lib.fileset rejects string-like values outright, but a flake input,
        # `inputs.self` and a plain store-path string all name a directory that
        # already exists, so recover the path they name instead of giving up.
        else if !lib.isDerivation src && lib.isStringLike src then
          /. + "${src}"
        else
          null;

      # A missing SDK directory means the layout is not the one `defaults`
      # assumes, so keep the whole tree rather than hand the builder an empty
      # one. A caller-supplied `srcPaths` is taken at its word instead; the
      # individual paths in either list may be missing without failing.
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
