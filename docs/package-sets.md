# Package sets

A package set is a named, versioned group of Pulumi packages built against one set of pinned inputs.
It is what a channel is made of: [`unmango/pulumipkgs`](https://github.com/unmango/pulumipkgs) publishes `stable` and `nightly` as two of these, and an org publishes its approved set as a third, derived from one of them.

Every other builder in this repo produces one Pulumi artifact.
A package set produces none.
It is a scope over the artifacts, which is why it is absent from the tables in [architecture.md](architecture.md).

## The shape

```nix
{ mkPackageSet, pkgs }:
mkPackageSet {
  name = "stable";
  version = "2026.09.1";

  pins = {
    inherit (pkgs) pulumi nodejs;
    inherit (pkgs.pulumiPackages) pulumi-nodejs pulumi-python pulumi-go;
  };

  packages = {
    random = ./pkgs/random;
    command = ./pkgs/command;
  };
}
```

Members are `callPackage`d in the set's scope, so `./pkgs/random/default.nix` takes what it needs by name:

```nix
{ mkTerraformBridgeProvider, pulumi-nodejs }:
mkTerraformBridgeProvider rec {
  owner = "pulumi";
  repo = "pulumi-random";
  version = "4.14.0";
  # ...
  sdks.nodejs.languagePlugin = pulumi-nodejs;
}
```

That resolves `mkTerraformBridgeProvider` from this repo's builders, `pulumi-nodejs` from the set's pins, and everything else from `pkgs`.
Members can name each other for the same reason, which is how a component that imports another provider's SDK is expressed.

The result:

| Field | What it is |
| --- | --- |
| `name`, `version` | the set's identity. `version` is the set's own, bumped when any member changes |
| `members` | `{ <name> = drv; }` |
| `plugins` | the members that carry a plugin identity, so a schema-only member is excluded |
| `schemas`, `sdks.<lang>` | folded out of each member's `passthru` |
| `scope` | the scope itself, for reaching a pin as `set.scope.pulumi` |
| `manifest`, `manifestData` | identity of the set and every member, as JSON and as Nix |
| `all` | a `linkFarm` over every member: the "does this channel build" target |
| `env` | a plugin cache over a selection of `plugins` |
| `extend` | a derived set |
| `overrideScope` | the scope's own override, for changing a member's inputs rather than replacing it |

## Channels

A derived channel is a diff against its parent, not a copy of it.

```nix
packageSets.stable = mkPackageSet { /* as above */ };

packageSets.nightly = packageSets.stable.extend {
  name = "nightly";
  version = "2026.09.1-nightly";
  packages.random = ./pkgs/random-next;
};

packageSets.acme = packageSets.stable.extend {
  name = "acme";
  version = "1.0.0";
  packages.random = ./pkgs/random-4.13;   # the org holds one provider back
};
```

`extend` takes the same arguments `mkPackageSet` does and merges them over the parent's.
Use `overrideScope` instead to change what a member is built *with* while leaving which member it is alone.

## Caching

Three facts, and they are the reason the abstraction exists rather than a side benefit of it.

**A member's hash does not depend on the set's membership.**
It depends on the member's own inputs and the set's pins.
Two sets sharing a pin set and a member version produce one store path, so a binary cache hit crosses channels and orgs.

**`extend` rebuilds what it replaces, and nothing else.**
`packageSets.acme` above rebuilds `random` and anything downstream of it.
`command` is a cache hit.
`checks.package-set` asserts exactly this.

**Which members a consumer uses enters only `env`.**
Without a set, a consumer assembling their own group of plugins produces a derivation per combination, and every combination is a fresh miss.
With one, the combination lands in `mkPulumiEnv`, a `runCommandLocal` that writes symlinks over packages that are already built.
It is cheap enough that it is built locally rather than fetched.

## Environments

`set.env` assembles a selection into the two shapes a Pulumi program can consume:

```nix
env = set.env { plugins = [ set.members.random ]; };
```

- `$out/plugins/resource-<name>-v<version>/` is Pulumi's plugin cache layout, and the general form.
  A component provider is a source tree with no binary, so this is the only route that covers one.
- `$out/bin/` holds the plugin binaries plus the set's pinned CLI, for Pulumi's ambient plugin resolution off `PATH`.
- `passthru.seedScript` copies `$out/plugins` into `$PULUMI_HOME/plugins`.

The seed script is the route a sandboxed build has to take.
Pulumi writes to `$PULUMI_HOME` as it runs, so `$PULUMI_HOME` cannot be a store path, and the cache has to be copied into a writable directory first.
[`mkComponentSchema`](usage.md#mkcomponentschema)'s `providerPlugins` is the same mechanism.

Two plugins claiming one cache entry or one binary name fails the `env` build rather than picking one silently.

## Plugin identity

A package states which Pulumi plugin it is in one of two ways, and `pluginRef` reads either.

- A compiled provider sets `meta.mainProgram` to `pulumi-resource-<name>` and serves the binary from `$out/bin`.
  [`mkProviderPlugin`](usage.md#mkproviderplugin) and [`mkDynamicPlugin`](usage.md#mkdynamicplugin) do this.
- A component provider has no binary, so [`mkComponentPlugin`](usage.md#mkcomponentplugin) sets `passthru.pulumiPlugin = { name; subdir; }` instead.

A package that declares neither can still go into an `env` as an explicit `{ name, version, plugin }`.

## The manifest

`manifest` is a JSON file recording the set's identity and each member's.
It holds no store paths, so reading or building it does not force the members.

```json
{
  "schemaVersion": 1,
  "set": { "name": "stable", "version": "2026.09.1" },
  "pins": { "pulumi": "3.255.0" },
  "packages": {
    "random": { "version": "4.14.0", "plugin": "random", "sdks": ["python"], "schema": true }
  }
}
```

It is enough to audit a set, diff two channels, and let an org state what it approved.
`all` is the separate target that builds every member.
