# Known Gaps

## Go SDK generation from a schema (component-provider pipeline)

`lib/mk-generated-sdk.nix` shells out to `pulumi package gen-sdk` to turn a `schema.json` into a language SDK's source tree, for packages whose SDK isn't fetched from an upstream repo (component providers, see `lib/mk-component-package.nix`).

This works for `nodejs` and `dotnet` (both proven end to end, see `examples/test-component/`). `go` does not work yet.

### The problem

`pulumi package gen-sdk --language go` (with or without `--local`) emits only `.go` source files - no `go.mod`/`go.sum`. Unlike nodejs's `package.json` and dotnet's `.csproj`, which the per-language codegen emits directly, a Go module's path is external convention that upstream provider repos define via their own build tooling, not something the schema/codegen carries.

Confirmed by fetching `pulumi-command`'s real, hand-maintained `sdk/go.mod` from GitHub: a full `require`/`// indirect` block, clearly produced by `go mod tidy` and checked in, not codegen output.

A bare `go mod init <path>` fixup is not enough. `lib/sdks/go.nix`'s `buildGoModule` vendoring step does not auto-resolve missing `require` entries from source imports - confirmed via an actual failed build:

```
go: github.com/pulumi/pulumi-command/sdk/go/command imports
    github.com/blang/semver: no required module provides package github.com/blang/semver; to add it:
    go get github.com/blang/semver
```

Populating `go.mod`'s `require` block and `go.sum` correctly needs a real `go mod tidy`, which needs network access. That can't happen in a normal sandboxed derivation phase.

### What's needed

A fixed-output-derivation-shaped fixup step, the same pattern `buildGoModule`'s own vendoring phase already uses (`vendorHash`, caller-supplied, network-permitted inside the FOD only):

1. Take `mk-generated-sdk.nix`'s raw go output (`.go` source files only).
2. Run `go mod init <importBasePath>` - the module path is derivable from the schema itself (`language.go.importBasePath`, confirmed present in `pulumi-command`'s `schema.json`).
3. Run `go mod tidy` inside a fixed-output derivation (network-permitted, caller supplies the expected output hash - e.g. a new `goModTidyHash` arg).
4. Output the completed `go.mod` + `go.sum` (or the whole tree with them added) in the shape `lib/sdks/go.nix` already expects (`${src.name}/sdk/go.mod`, `${src.name}/sdk/go.sum`, `${src.name}/sdk/go/...`).

Candidate shapes: a new file (e.g. `lib/mk-generated-go-sdk-modfile.nix`) composed after `mk-generated-sdk.nix`'s go case, or a `go`-specific branch within `mk-generated-sdk.nix` itself gated on a new hash arg. Whichever shape, `lib/sdks/go.nix` itself should not need to change - it already just expects `go.mod`/`go.sum` to exist in its `src`.

### Where this plugs in

- `lib/with-generated-sdks.nix` would gain the ability to accept `goArgs` once this exists (today it works generically for any `sdkBuilders` key, so no change needed there beyond the go.mod fixup itself existing).
- `examples/test-component/` would be the natural place to prove it end to end, mirroring how `nodejsArgs`/`dotnetArgs` are proven there already.

### Status

Deferred by explicit decision - does not block nodejs or dotnet, which are fully working. See `/Users/erasmussen/.claude/plans/design-the-component-package-gentle-hickey.md` (milestone 2b) for the full investigation history, including the exact failed-build output and the reasoning that ruled out simpler fixes.
