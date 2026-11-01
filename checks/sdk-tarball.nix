# The `tarball` output is what a consumer that can only `npm install` or
# `bun install` depends on, so it has to carry `@pulumi/pulumi` as a dependency
# even though the store output leaves its copy out, and nothing else but the
# package itself.
{
  pkgs,
  sdk,
  fileName,
}:
pkgs.runCommandLocal "sdk-tarball" { nativeBuildInputs = [ pkgs.jq ]; } ''
  fail() {
    echo "sdk-tarball: $*" >&2
    exit 1
  }

  tarballs=(${sdk.tarball}/*.tgz)
  [ "''${#tarballs[@]}" -eq 1 ] || fail "expected one .tgz, found: ''${tarballs[*]}"
  [ "$(basename "''${tarballs[0]}")" = "${fileName}" ] \
    || fail "expected ${fileName}, found $(basename "''${tarballs[0]}")"

  tar -xzf "''${tarballs[0]}"
  for file in index.js index.d.ts package.json README.md LICENSE; do
    test -f "package/$file" || fail "package/$file missing"
  done
  [ ! -e package/node_modules ] || fail "tarball bundles node_modules"

  [ "$(jq -r .version package/package.json)" = "${sdk.version}" ] \
    || fail "package.json version is not ${sdk.version}"
  jq -e '.dependencies["@pulumi/pulumi"]' package/package.json >/dev/null \
    || fail "package.json lost its @pulumi/pulumi dependency"

  touch $out
''
