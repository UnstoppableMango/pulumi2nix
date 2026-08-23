# Picks out the caller args that select per-language SDK builds (e.g. `nodejsArgs`,
# `goArgs`) so they can be stripped before forwarding the rest to the base builder.
# `pythonArgs` is excluded: the base builder handles it natively.
{ lib }:
args: lib.filter (name: name != "pythonArgs" && lib.hasSuffix "Args" name) (builtins.attrNames args)
