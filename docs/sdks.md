# Sources and SDKs

## Overriding the source

Every builder that fetches an upstream provider accepts an optional `src`, defaulting to a `fetchFromGitHub` of `owner`/`repo`/`rev`/`hash`:

```nix
mkTerraformBridgeProvider {
  repo = "pulumi-random";
  version = "4.14.0";
  src = ./my-checkout; # or fetchgit, fetchzip, a flake input, ...
  vendorHash = "sha256-...";
  cmdGen = "pulumi-tfgen-random";
  cmdRes = "pulumi-resource-random";
}
```

`owner` and `hash` are only forced by the default fetch, so a caller supplying `src` can omit them.
`repo` is required either way, and `rev` defaults to `v${version}`: both name the derivation.
Layered SDKs take a lang-qualified name, `<repo>-sdk-<lang>`, matching the flattened `packages.<name>-sdk-<lang>` output; set `pname` on the `sdks.<lang>` block to override.

`sourceRoot` is resolved from the `src`'s name, so any fetcher output, a `lib.cleanSourceWith`, a plain path, and a store path all work.
`lib.fileset.toSource` is preferred, because it names its result explicitly instead of leaving the name to be recovered from a store path:

```nix
src = lib.fileset.toSource {
  root = ./.;
  fileset = lib.fileset.unions [ ./provider ./sdk ];
};
```

Note that `src = ./.` inside a flake only sees git-tracked files.

## Narrowed SDK sources

The provider, the schema and every checked-in SDK share one `src`, but each SDK only builds from its own subtree, so each is handed a `lib.fileset`-narrowed copy.
Editing a file no SDK reads (a README, a CI workflow, the Makefile) then no longer rebuilds them.

| SDK | Paths kept |
| --- | --- |
| `sdks.go` | `sdk/go`, `sdk/go.mod`, `sdk/go.sum` |
| `sdks.nodejs`, `sdks.yarnNodejs` | `sdk/nodejs`, `README.md`, `LICENSE` |
| `sdks.dotnet` | `sdk/dotnet` |
| `sdks.python` | `sdk/python` |

`README.md` and `LICENSE` are in the nodejs list because the SDK build copies them next to its compiled output.
Missing paths are skipped rather than failing, and if the SDK's own directory is missing the whole tree is kept.
The schema build always keeps the whole tree, since the gen tool runs from the repo root and tfgen reads the upstream provider's docs; so does the plugin build, which needs the whole Go module.
Narrowing needs a tree readable at eval time, so a `src` that is still an unbuilt derivation (the default fetch) is passed through untouched, which costs nothing: that output only moves when `rev` does.

Two per-SDK escape hatches, for a repo whose SDK build reads outside its own directory:

```nix
sdks.nodejs = {
  lockFile = ./package-lock.json;
  npmDepsHash = "sha256-...";

  narrowSrc = false; # keep the whole tree for this SDK

  # ...or replace the default path list. Missing paths are skipped.
  srcPaths = [ "sdk/nodejs" "README.md" "LICENSE" "scripts/postinstall.js" ];
};
```

Both are also accepted directly as `nodejsArgs.narrowSrc`, `goArgs.srcPaths`, and so on.

## Consuming a nodejs SDK

A nodejs SDK - checked in or generated, npm or yarn - lands at `$out/lib/node_modules/<pkgName>`, holding the compiled output of `sdk/nodejs` plus its `package.json`, `README.md` and `LICENSE`.

Copy it into your project rather than symlinking:

```sh
mkdir -p node_modules/@unmango
cp -rL "$sdk/lib/node_modules/@unmango/pulumi-git" node_modules/@unmango/pulumi-git
```

Node and bun both resolve from the *realpath* of a symlink, so a symlinked SDK would look for `@pulumi/pulumi` under `/nix/store` and never see the one your program uses.

`@pulumi/pulumi` is not shipped inside the output.
It has to be a *singleton* in the consuming process, since Pulumi's Node runtime keeps the resource monitor address and stack config at module scope, so a second copy is a second, unconfigured runtime.
Leaving it out also drops its transitive tree, which is most of the output: the `pulumi-command` example's nodejs SDK went from 165M to 200K.
The `package.json` is upstream's, untouched, so a package manager pointed at the store path installs it for you.

To change what is left out:

```nix
sdks.nodejs = {
  lockFile = ./package-lock.json;
  npmDepsHash = "sha256-...";

  # Default: [ "@pulumi/pulumi" ]. `[ ]` ships the whole pruned tree.
  omitDeps = [ "@pulumi/pulumi" "@pulumi/aws" ];
};
```

npm drops the named packages before pruning, so anything reachable only through them goes too.
Yarn classic has no real `prune`, so `sdks.yarnNodejs` deletes them afterwards and their orphaned transitive dependencies stay behind; nothing resolves to those, but the output carries them.

## SDK drift checks

`mkTerraformBridgeProvider` reads committed SDKs straight out of `sdk/<lang>`, so a resource change landing without a regenerated SDK still builds and `nix flake check` stays green against a stale tree.
`sdkDrift.languages` closes that loop: per language it `diff -r`s the committed tree against one the provider's own `cmdGen` just emitted, and emits `checks.<name>-sdk-<lang>-drift`.
The check never appears in `packages`, since its output is an empty marker file.

Both sides are [`mkSdkSource`](usage.md#mksdksource) trees, so the check itself generates nothing.
The gen tool is the default generator rather than `gen-sdk` because it is the only route that replays tfgen's language overlays, which is exactly what a provider committing an SDK tree tends to have.
Call [`mkSdkDriftCheck`](usage.md#mksdkdriftcheck) directly to diff against a schema-generated tree instead.

```nix
pulumi.terraformBridgeProviders.pulumi-foo = {
  # ...
  sdkDrift.languages = [ "nodejs" "python" "go" "dotnet" ];
};
```

That plain list assumes the gen tool emits every language itself, in-process and offline.
On a current [`pulumi-terraform-bridge`](https://github.com/pulumi/pulumi-terraform-bridge), [`pkg/tfgen`](https://github.com/pulumi/pulumi-terraform-bridge/tree/master/pkg/tfgen)'s `emitSDK` instead shells out to [`pulumi package gen-sdk --language <lang>`](https://www.pulumi.com/docs/iac/cli/commands/pulumi_package_gen-sdk/), so the check needs the `pulumi` CLI and that language's host on `PATH` or it dies with `exec: "pulumi": executable file not found in $PATH`.
Say so with an attrset instead of a list:

```nix
sdkDrift.languages = {
  nodejs.languagePlugin = pkgs.pulumiPackages.pulumi-nodejs;
  python.languagePlugin = pkgs.pulumiPackages.pulumi-python;
  go.languagePlugin = pkgs.pulumiPackages.pulumi-go;
  dotnet = {
    languagePlugin = pulumi2nix.pulumiLanguageDotnet;
    extraExclude = [ "logo.png" ];
  };
};
```

Which era a provider is on is left to you: it follows from the bridge version in its own `provider/go.mod`, which nothing here can read at eval time.
A missing plugin fails the check outright; an unnecessary one drags the `pulumi` closure into a build that never invokes it.
`dotnet` wants `extraExclude = [ "logo.png" ]` because `pulumiLanguageDotnet` emits the generic icon, so a committed SDK whose logo came from a real `logoUrl` always reads as drift.
Anything set on a language (`exclude`, `extraExclude`, `sdkPath`) overrides the surrounding `sdkDrift` block for that language alone.
`exclude` is the list of basenames `diff -r` skips, defaulting to `package-lock.json`, `go.mod`, `go.sum` and `version.txt`, the files tfgen never emits; `extraExclude` adds rather than replaces.

Drift checking is off by default, since it only makes sense where the committed SDK is reproducible from the pinned source: the repo must commit an `sdk/` tree, its generation step must be a plain `cmdGen <lang> --out sdk/<lang>` with no post-processing, and the gen tool must find its documentation offline.
Bridged providers pulling doc comments out of an upstream Terraform provider's `website/docs` cannot, since `go mod vendor` keeps only `.go` files; [`examples/pulumi-random`](../examples/pulumi-random) documents that case.
Greenfield bridged providers, whose `make generate` is nothing but a tfgen invocation per language, are the case this is built for.

## Generated SDKs for bridged providers

The other answer to a stale `sdk/` tree is not to commit one.
`sdks.<lang>.generate = true` codegens that language from the declaration's own `passthru.schema`, so the tree and the `make generate` maintaining it can be deleted.

```nix
pulumi.terraformBridgeProviders.pulumi-foo = {
  # ...
  sdks.nodejs = {
    generate = true;
    languagePlugin = pkgs.pulumiPackages.pulumi-nodejs;
    lockFile = ./package-lock.json;
    npmDepsHash = "sha256-...";
  };

  sdks.python = {
    generate = true;
    languagePlugin = pkgs.pulumiPackages.pulumi-python;
  };
};
```

Pick one per language, not both: a generated SDK has no committed counterpart for `sdkDrift` to diff.
Languages left alone keep building from the repo, so a provider can generate some and commit others.
This runs [`pulumi package gen-sdk`](https://www.pulumi.com/docs/iac/cli/commands/pulumi_package_gen-sdk/) through [`mkSdkSource`](usage.md#mksdksource), against the schema `checks.<name>-schema` already builds, so each language needs its own `languagePlugin` for the same reason the drift check does.

**Limitation: language overlays are not applied.**
tfgen's per-language overlays (`info.JavaScript.Overlay` and friends, the hand-written files a `resources.go` splices into its SDKs) are not part of the [package schema](https://www.pulumi.com/docs/iac/guides/building-extending/packages/schema/), so a provider shipping overlays gets an SDK that silently lacks them.
That provider should keep its committed tree and guard it with `sdkDrift` instead.

**What still comes from the caller.**
`gen-sdk` emits language sources and nothing else, so module files stay required exactly as for a committed tree:

- `nodejs` / `yarnNodejs`: `lockFile` + `npmDepsHash`, or `yarnLockFile` + `yarnDepsHash`.
- `go`: `vendorHash`, plus `importBasePath`, `goMod` and `goSum` - see [`mkSdkSource`](usage.md#mksdksource).
- `dotnet`: `nugetDeps`.
- `python`: nothing. `generate` and `languagePlugin` are all `sdks.python` takes.

`narrowSrc` / `srcPaths` do not apply to a generated language: its source is codegen output, already scoped to one language.

## Python SDKs

Python is an ordinary language here, opt-in like every other: `sdks.python = { }` builds the repo's committed `sdk/python`, and adding `generate = true` plus a `languagePlugin` codegens it instead.
The same block works on a component provider, which had no python SDK at all before.

One argument is python-specific.
`distName` is the name the SDK distributes under, which follows the plugin rather than the repo: `cmdRes = "pulumi-resource-random"` gives `pulumi-random`, whatever the repo is called.
It drives `pythonImportsCheck` (dashes to underscores) and the version check the build runs against `pip show`.
The provider recipes default it from `cmdRes`, so a bridged or native provider needs it only for an SDK that does not follow the convention.

A component provider always has to say.
Its generated SDK distributes under the *schema's* package name, which `pulumi package get-schema` reads out of `package.json` rather than from `pname`, so nothing here can derive it at eval time:

```nix
sdks.python = {
  languagePlugin = pkgs.pulumiPackages.pulumi-python;
  distName = "pulumi_test_component_schema";
};
```

Read the right value off the schema (`nix build .#your-package-schema` then `jq -r .name`), prefixed with `pulumi_` and with `-` replaced by `_`.
Getting it wrong fails the build with `Package(s) not found: <name>` followed by `ERROR: Version substitution seems to be broken`.
