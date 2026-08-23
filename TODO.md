# Known Gaps

## Java SDK generation

`lib/mk-generated-sdk.nix` can drive any language `pulumi package gen-sdk` supports, but nixpkgs' `pulumiPackages` has no `pulumi-language-java` to pass as `languagePlugin`, and there's no pinned build for it here the way `lib/pulumi-language-dotnet.nix` fills the .NET gap.
Closing this means packaging `pulumi/pulumi-java`'s language host, then registering a `java` entry in `lib/sdks/default.nix`.

## Python SDKs for component providers

`lib/with-generated-sdks.nix` throws on `pythonArgs`: only the languages registered in `lib/sdks` (nodejs, yarnNodejs, go, dotnet) are available for source-based component providers.
`mkPulumiPackage`/`mkTerraformBridgeProvider` don't have this gap - they delegate python to nixpkgs' upstream builder, which has no equivalent for a generated SDK tree.

## `pulumi package gen-sdk --language dotnet` needs network

The dotnet codegen fetches `pulumi_logo_64x64.png` from `raw.githubusercontent.com` while writing the SDK, so `mkGeneratedSdk` with `lang = "dotnet"` fails in a sandboxed build with a DNS error.
Unlike the Go module-file gap, this isn't a missing-input problem: the fix is to pre-seed or vendor that asset (or patch the icon reference out of the generated `.csproj`) before codegen runs.

## Generated SDKs aren't covered by CI

`flake.nix` exposes only the base derivations through `packages`/`checks`, so `nix flake check` never builds `passthru.sdks.*`.
Every per-language SDK build is verified by hand (`nix build .#test-component.sdks.go`), which is how the dotnet gap above went unnoticed.
