# Narrows a provider repo's `src` down to the subtree one language's SDK build
# actually reads, so an unrelated file change doesn't move that SDK's input
# hash. `sourceRoot` already selects the subtree at build time, but without
# this narrowing, the README, the CI config and every other file in the repo
# are inputs to all four SDK derivations, so editing any of them rebuilds
# every one.
#
# Only a tree readable at eval time can be narrowed: a path, or any value that
# stringifies to a store path already realized on disk. A `src` that is still
# an unbuilt derivation, such as the default `fetchFromGitHub` fetch, is
# returned unchanged, since `lib.fileset` cannot look inside one without
# building it first and a fetch's output only moves when `rev` does. That
# makes this a no-op for the common `owner`/`repo`/`rev`/`hash` path and a real
# saving for the local-checkout workflow.
{ lib }:
let
  # Repo-relative paths each language's SDK build reads. `dir` is the one
  # `sourceRoot` points at; `extra` are files the build reaches for outside it,
  # e.g. lib/sdks/npm.nix copies `../../README.md ../../LICENSE` in `postBuild`,
  # and a Pulumi go SDK's module root is `sdk/go.mod`, one level above `sdk/go`.
  # `extra` is optional for a language that reads nothing outside `dir`.
  defaults = rec {
    nodejs = {
      dir = "sdk/nodejs";
      extra = [
        "README.md"
        "LICENSE"
      ];
    };

    # Same tree as nodejs, built by a different tool.
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

      paths = langArgs.srcPaths or (if spec == null then null else [ spec.dir ] ++ (spec.extra or [ ]));

      root =
        if builtins.isPath src then
          src
        # lib.fileset rejects string-like values outright, but a string-like
        # value naming an existing directory still points at a readable tree,
        # so recover the path it names instead of giving up. The context has
        # to go, or Nix refuses the append: "a string that refers to a store
        # path cannot be appended to a path"; discarding it is safe because
        # `root` never reaches a derivation, only `builtins.pathExists` and
        # `lib.fileset.maybeMissing` during evaluation.
        else if !lib.isDerivation src && lib.isStringLike src then
          /. + (builtins.unsafeDiscardStringContext "${src}")
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
