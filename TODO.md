# Known Gaps

## pulumipkgs' `pulumi-dotnet` cannot run .NET codegen

`integration/` builds `test-component`'s dotnet SDK with `pkgs.pulumiPackages.pulumi-dotnet` from unmango/pulumipkgs, and that check is expected to fail today.
Upstream's `getLogo()` in `pulumi-language-dotnet/codegen/gen.go` downloads `logo.png` over HTTP, which the build sandbox forbids, so `pulumi package gen-sdk --language dotnet` cannot run against an unpatched language host.
This repo works around it in `lib/pulumi-language-dotnet.nix` with a vendored `fetchurl` logo plus `lib/patches/pulumi-language-dotnet-offline-logo.patch`; pulumipkgs ships the same binary without either.
Closing this means porting that patch into pulumipkgs' `pkgs/languages/pulumi-dotnet`, rebasing it from 3.110.0 onto its 3.112.1, after which `lib/pulumi-language-dotnet.nix` can be retired in favour of the package set.
Note the version bump may also change the generated `.csproj`, so `integration/` may then need its own `nugetDeps` deps.json rather than the example's.

## Java SDK generation

`lib/mk-generated-sdk.nix` can drive any language `pulumi package gen-sdk` supports, but nixpkgs' `pulumiPackages` has no `pulumi-language-java` to pass as `languagePlugin`, and there's no pinned build for it here the way `lib/pulumi-language-dotnet.nix` fills the .NET gap.
Closing this means packaging `pulumi/pulumi-java`'s language host, then registering a `java` entry in `lib/sdks/default.nix`.

## Python SDKs for component providers

`lib/with-generated-sdks.nix` throws on `pythonArgs`: only the languages registered in `lib/sdks` (nodejs, yarnNodejs, go, dotnet) are available for source-based component providers.
`mkPulumiPackage`/`mkTerraformBridgeProvider` don't have this gap - they delegate python to nixpkgs' upstream builder, which `mk-terraform-bridge-provider.nix` points at `mkGeneratedSdk` output when `sdks.python.generate` is set, sidestepping `with-generated-sdks.nix` entirely.
Registering that path in `lib/sdks` would close this properly, but a component provider's python SDK also needs the version/`pkg_resources` patching `mkPythonPackage` carries, which currently lives in the bridge builder rather than in a reusable SDK builder.
The flake module mirrors this: `pulumi.componentPackages.<name>.sdks` has no `python` option, while `pulumi.nativeProviders`/`terraformBridgeProviders` do.

## Generated bridged SDKs do not get tfgen's language overlays

`sdks.<lang>.generate = true` (see the README) codegens a bridged provider's SDK from its schema with `pulumi package gen-sdk`, which is the same command a current tfgen delegates to, but it is only the codegen step.
tfgen's per-language overlays - `info.JavaScript.Overlay`, `info.Golang.Overlay` and friends, the hand-written files a provider's `resources.go` splices into its SDKs around codegen - are not represented in the schema, so nothing downstream of it can replay them.
A provider that ships overlays gets an SDK that silently lacks them, and has to keep its committed `sdk/` tree with an `sdkDrift` check instead.
Closing this means running the provider's own `cmdGen <lang>` as the generator rather than `gen-sdk`, which is a second generator to build and maintain, and on a delegating bridge needs the `pulumi` CLI and the language plugin anyway.

## No example exercises `sdkDrift.languages` in its attrset form

`sdkDrift.languages` takes a plain list for a pre-delegation bridge and an attrset of `{ languagePlugin = ...; }` for one whose tfgen shells out to `pulumi package gen-sdk`.
Only the list form appears in `examples/`, and only as a comment: `examples/pulumi-random` pins 4.14.0, whose bundled bridge still codegens in-process.
Covering the attrset form end to end means a full Go build of a provider on a current bridge, which no example here does, so both shapes are currently verified by evaluation only - that the option type accepts each and that the plugin reaches `nativeBuildInputs`.
Whether the generator actually runs under a delegating tfgen has been confirmed only against the downstream consumer in issue #61, not in this repo's CI.

## Drift checks against providers that vendor their docs

`sdkDrift` is exact only where the gen tool can reproduce the committed SDK offline.
Bridged providers that source doc comments from an upstream Terraform provider's `website/docs` cannot: nixpkgs vendors Go dependencies with `go mod vendor`, which keeps only `.go` files, so tfgen regenerates every resource with "could not find docs for resource ..." and the diff is all doc comments.
`examples/pulumi-random` documents the case and leaves the check off.
Closing it means getting the upstream module's non-Go files into the gen tool's environment, which nixpkgs' `buildGoModule` vendoring does not currently offer.
