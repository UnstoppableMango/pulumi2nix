# Shared by with-sdks.nix, with-generated-sdks.nix, and mk-pulumi-package.nix:
# picks out the caller args that select per-language SDK builds (e.g.
# `nodejsArgs`, `goArgs`) from the rest of a builder's args, so they can be
# stripped before forwarding the remainder to the base provider builder.
# `pythonArgs` is deliberately excluded from that selection: the base
# provider builder (ported from nixpkgs' own mk-pulumi-package.nix in
# lib/mk-terraform-bridge-provider.nix) already understands `pythonArgs`
# natively and packages the python SDK itself, so it must stay in the args
# forwarded to that base builder untouched - it is not one of *this*
# repo's `lib/sdks`-driven `<lang>Args` blocks, and is not dropped.
{ lib }:
args: lib.filter (name: name != "pythonArgs" && lib.hasSuffix "Args" name) (builtins.attrNames args)
