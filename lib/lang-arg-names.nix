{ lib }:
let
  # A component package's schema-extraction block, not a language. Every other
  # `<name>Args` key is read as one, python included.
  reserved = [ "schemaArgs" ];
in
args:
lib.filter (name: !(lib.elem name reserved) && lib.hasSuffix "Args" name) (builtins.attrNames args)
