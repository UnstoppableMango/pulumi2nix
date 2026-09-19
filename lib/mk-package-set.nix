# A named, versioned group of Pulumi packages built against one set of pinned
# inputs. This is what a channel is: `unmango/pulumipkgs` publishes `stable` and
# `nightly` as two of these, and an org publishes its approved set as a third,
# derived from one of them.
#
# The set is a nixpkgs-style scope, so a member's `default.nix` takes what it
# needs by name - `{ mkTerraformBridgeProvider, pulumi, pulumi-nodejs }` - and
# gets the set's pins rather than whatever the caller's `pkgs` happened to have.
# Members can name each other for the same reason, which is how a component that
# imports another provider's SDK is expressed.
#
# Three facts about caching follow from that, and they are the point:
#
#   - A member's derivation hash depends on its own inputs and the set's pins,
#     never on the set's membership. Two sets sharing a pin and a version
#     produce one store path, so a cache hit crosses channels.
#   - `extend` rebuilds the members it replaces and their dependents. The rest
#     keep their paths.
#   - Which members a consumer actually *uses* enters only `env`, a symlink
#     tree. That is the only per-selection derivation, and it is free.
{
  lib,
  newScope,
  linkFarm,
  writeText,
  mkPulumiEnv,
  pluginRef,

  # The builders as uninstantiated paths, `<name> -> path`. They are
  # `callPackage`d inside the set's own scope so that a builder's *own* inputs
  # resolve through the pins too: a member calling `mkTerraformBridgeProvider`
  # gets one whose nested `mkSdkSource` sees `pins.pulumi`, not the outer
  # `pkgs.pulumi`.
  builders,
}:
let
  mkPackageSet =
    {
      # The channel name: "stable", "nightly", an org's name.
      name,

      # The set's own version, bumped whenever a member changes. Not any
      # member's version; it is what a consumer pins to say "this group, as a
      # group".
      version,

      # Members, as `<name> -> path | function`, each `callPackage`d in the
      # scope.
      packages ? { },

      # Shared inputs every member resolves by name, layered over `pkgs`: the
      # `pulumi` CLI, the `pulumi-language-*` hosts, a terraform bridge revision.
      pins ? { },

      # Applied last, for overriding a member's *inputs* rather than replacing
      # it. `extend` is the coarser tool, and the one channels want.
      overrides ? (_final: _prev: { }),
    }@args:
    let
      scope = lib.makeScope newScope (
        self:
        lib.mapAttrs (_: path: self.callPackage path { }) builders
        // pins
        // lib.mapAttrs (_: value: self.callPackage value { }) packages
      );

      final = scope.overrideScope overrides;

      members = lib.genAttrs (lib.attrNames packages) (n: final.${n});

      passthruOf = m: m.passthru or { };

      # A member is a plugin when it declares a plugin identity either way
      # `pluginRef` accepts. A schema-only member declares neither, and belongs
      # in a set without belonging in a plugin cache.
      isPlugin = m: (passthruOf m) ? pulumiPlugin || (m.meta or { }) ? mainProgram;

      plugins = lib.filterAttrs (_: isPlugin) members;

      schemas = lib.filterAttrs (_: v: v != null) (
        lib.mapAttrs (_: m: (passthruOf m).schema or null) members
      );

      languages = lib.unique (
        lib.concatMap (m: lib.attrNames ((passthruOf m).sdks or { })) (lib.attrValues members)
      );

      sdks = lib.genAttrs languages (
        lang:
        lib.filterAttrs (_: v: v != null) (
          lib.mapAttrs (_: m: ((passthruOf m).sdks or { }).${lang} or null) members
        )
      );

      # Identity only, no store paths, so reading or building the manifest
      # doesn't force every member. `all` is the target that builds the set.
      manifestData = {
        schemaVersion = 1;
        set = { inherit name version; };
        pins = lib.mapAttrs (_: p: p.version or null) pins;
        packages = lib.mapAttrs (n: m: {
          inherit (m) version;
          plugin = if isPlugin m then (pluginRef m).name else null;
          sdks = lib.attrNames ((passthruOf m).sdks or { });
          schema = schemas ? ${n};
        }) members;
      };
    in
    {
      inherit
        name
        version
        members
        plugins
        schemas
        sdks
        manifestData
        ;

      # The scope itself, for reaching a pin (`set.scope.pulumi`) or for
      # `overrideScope` when `extend` is too coarse.
      scope = final;
      inherit (final) overrideScope;

      manifest = writeText "${name}-${version}-manifest.json" (builtins.toJSON manifestData);

      # "Does this channel build." One link per member.
      all = linkFarm "${name}-${version}" members;

      # A plugin cache over a selection of this set's plugins, defaulting to all
      # of them, with the set's pinned CLI.
      env =
        envArgs:
        mkPulumiEnv (
          {
            name = "${name}-env";
            plugins = lib.attrValues plugins;
            pulumi = pins.pulumi or null;
          }
          // envArgs
        );

      # A derived set: same shape, with members added or replaced. This is how
      # an org set stays a diff against `stable` rather than a copy of it.
      extend =
        overlay:
        mkPackageSet (
          args
          // overlay
          // {
            packages = packages // (overlay.packages or { });
            pins = pins // (overlay.pins or { });
            overrides = lib.composeExtensions overrides (overlay.overrides or (_final: _prev: { }));
          }
        );
    };
in
mkPackageSet
