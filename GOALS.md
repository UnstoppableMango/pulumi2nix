# Project Goals

Provide composable builders for building pulumi providers and packages.
Provide composable builders for generating language SDKs.
Provide builders for generating pulumi providers from terraform providers.

## Artifacts

A Pulumi package's build produces several distinct kinds of artifact.
This project aims to eventually cover each of them with a composable builder.

- Native provider plugin binaries (`pulumi-resource-<name>`), built directly against a Pulumi provider SDK.
- Bridged provider plugin binaries, generated from a wrapped Terraform provider via a `pulumi-tfgen-<name>` bridge.
- Component provider packages, which expose typed multi-language components as a provider plugin.
- Generated providers built from a non-Terraform schema source, such as the `*-native` providers generated from OpenAPI or CloudFormation resource schemas.
- Generated provider schema (`schema.json`), the package metadata every provider flavor above emits and that SDK generation consumes.
- Generated language SDKs (Node.js, Python, Go, .NET, Java), produced from a provider's schema and packaged with each language's own tooling.
