{ lib }:
args: lib.filter (name: name != "pythonArgs" && lib.hasSuffix "Args" name) (builtins.attrNames args)
