# Project Goals

Provide composable builders for building pulumi providers and packages.
Provide builders for building native provider plugin binaries (`pulumi-resource-<name>`), built directly against a Pulumi provider SDK.
Provide builders for generating pulumi providers from terraform providers, producing bridged provider plugin binaries via a `pulumi-tfgen-<name>` bridge.
Provide a builder for the generic, dynamically bridged `pulumi-resource-terraform-provider` binary, which bridges any terraform provider at runtime instead of being generated ahead-of-time for one specific upstream provider.
Provide builders for generating providers from non-Terraform schema sources, such as the `*-native` providers generated from OpenAPI or CloudFormation resource schemas.
Provide builders for building component provider packages, which expose typed multi-language components as a provider plugin.
Provide builders for generating a provider's schema (`schema.json`) independent of its plugin binary.
Provide composable builders for generating language SDKs (Node.js, Python, Go, .NET, Java) from a provider's schema.
