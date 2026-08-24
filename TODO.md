# Known Gaps

## `lib/pulumi-language-dotnet.nix` duplicates pulumipkgs' build

This repo pins its own patched `pulumi-language-dotnet` because nixpkgs has no build for it, and `pulumi package gen-sdk --language dotnet` cannot run in a sandbox against an unpatched host.
unmango/pulumipkgs now carries the same offline-logo patch in `pkgs/languages/pulumi-dotnet`, at 3.112.1 against the 3.110.0 pinned here, and `integration/` proves that build drives codegen successfully.
So there are two patched copies of one workaround, and only one of them tracks upstream releases.
Retiring the local copy means dropping `lib/pulumi-language-dotnet.nix` and `lib/patches/pulumi-language-dotnet-offline-logo.patch`, which is a breaking change: `pulumiLanguageDotnet` is public API through both `flake.lib` and `overlays.default`, and `examples/test-component` is its only in-repo consumer.
It would also make pulumipkgs a hard prerequisite for .NET SDK generation, which is a bigger dependency than this repo currently takes on.

## Java SDK generation

`lib/mk-sdk-source.nix` can drive any language `pulumi package gen-sdk` supports, but nixpkgs' `pulumiPackages` has no `pulumi-language-java` to pass as `languagePlugin`, and there's no pinned build for it here the way `lib/pulumi-language-dotnet.nix` fills the .NET gap.
Closing this means packaging `pulumi/pulumi-java`'s language host, then registering a `java` entry in `lib/sdks/default.nix`.

## Generated SDKs do not get tfgen's language overlays

`sdks.<lang>.generate = true` (see the README) codegens a bridged provider's SDK from its schema with `pulumi package gen-sdk`, which is the same command a current tfgen delegates to, but it is only the codegen step.
tfgen's per-language overlays - `info.JavaScript.Overlay`, `info.Golang.Overlay` and friends, the hand-written files a provider's `resources.go` splices into its SDKs around codegen - are not represented in the schema, so nothing downstream of it can replay them.
A provider that ships overlays gets an SDK that silently lacks them, and has to keep its committed `sdk/` tree with an `sdkDrift` check instead.

`lib/mk-sdk-source.nix`'s `genTool` producer is that other generator, and the drift check already uses it, so the remaining work is to let `sdks.<lang>` select it as the *build* source too rather than only as the comparison side.
What stops that being a plain flag is cost: on a delegating bridge the gen tool needs the `pulumi` CLI and the language plugin anyway, so a provider would pay for both routes to find out which one it is on.

## No example exercises `sdkDrift.languages` in its attrset form

`sdkDrift.languages` takes a plain list for a pre-delegation bridge and an attrset of `{ languagePlugin = ...; }` for one whose tfgen shells out to `pulumi package gen-sdk`.
Only the list form appears in `examples/`, and only as a comment: `examples/pulumi-random` pins 4.14.0, whose bundled bridge still codegens in-process.
Covering the attrset form end to end means a full Go build of a provider on a current bridge, which no example here does, so both shapes are currently verified by evaluation only - that the option type accepts each and that the plugin reaches `nativeBuildInputs`.
Whether the generator actually runs under a delegating tfgen has been confirmed only against the downstream consumer in issue #61, not in this repo's CI.
Its two halves are covered separately, though: `checks.sdk-drift` diffs fixture trees through `mkSdkDriftCheck`, and `checks.sdk-source-gen-tool` runs a real pre-delegation `cmdGen <lang> --out` through `mkSdkSource`.

## Drift checks against providers that vendor their docs

`sdkDrift` is exact only where the gen tool can reproduce the committed SDK offline.
Bridged providers that source doc comments from an upstream Terraform provider's `website/docs` cannot: nixpkgs vendors Go dependencies with `go mod vendor`, which keeps only `.go` files, so tfgen regenerates every resource with "could not find docs for resource ..." and the diff is all doc comments.
`examples/pulumi-random` documents the case and leaves the check off.
Closing it means getting the upstream module's non-Go files into the gen tool's environment, which nixpkgs' `buildGoModule` vendoring does not currently offer.
