# Known Gaps

## Java SDK generation

`lib/mk-generated-sdk.nix` can drive any language `pulumi package gen-sdk` supports, but nixpkgs' `pulumiPackages` has no `pulumi-language-java` to pass as `languagePlugin`, and there's no pinned build for it here the way `lib/pulumi-language-dotnet.nix` fills the .NET gap.
Closing this means packaging `pulumi/pulumi-java`'s language host, then registering a `java` entry in `lib/sdks/default.nix`.

## Python SDKs for component providers

`lib/with-generated-sdks.nix` throws on `pythonArgs`: only the languages registered in `lib/sdks` (nodejs, yarnNodejs, go, dotnet) are available for source-based component providers.
`mkPulumiPackage`/`mkTerraformBridgeProvider` don't have this gap - they delegate python to nixpkgs' upstream builder, which has no equivalent for a generated SDK tree.
The flake module mirrors this: `pulumi.componentPackages.<name>.sdks` has no `python` option, while `pulumi.nativeProviders`/`terraformBridgeProviders` do.
