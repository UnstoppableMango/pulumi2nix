# Shared by with-sdks.nix, with-generated-sdks.nix, and mk-pulumi-package.nix:
# picks out the caller args that select per-language SDK builds (e.g.
# `nodejsArgs`, `goArgs`) from the rest of a builder's args. `pythonArgs` is
# excluded - python SDKs are handled by nixpkgs' own base provider builder,
# not by anything in lib/sdks.
{ lib }:
args: lib.filter (name: name != "pythonArgs" && lib.hasSuffix "Args" name) (builtins.attrNames args)
