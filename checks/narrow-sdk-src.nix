# Coverage for lib/narrow-sdk-src.nix, which `examples/` cannot reach: every
# example leaves `src` at the default `fetchFromGitHub`, an unbuilt derivation
# that takes the pass-through branch before `root` is ever forced. So the two
# readable branches - the only ones that do any narrowing - shipped untested,
# and the string-like one turned out to throw at eval on the very value it was
# written for. These cases pin all three readable shapes plus the pass-through.
{
  lib,
  pkgs,
  narrowSdkSrc,
}:
let
  fixture = ./fixtures/provider;

  # What `narrow "nodejs"` has to leave behind: its own subtree, plus the two
  # files lib/sdks/npm.nix copies next to the compiled output. The go subtree
  # belongs to another language and `noise.txt` to no build at all, so both
  # being gone is the whole point of narrowing.
  expected = ''
    ./LICENSE
    ./README.md
    ./sdk/nodejs/index.ts
  '';

  narrowed = src: narrowSdkSrc.narrow "nodejs" src { };

  # `-type f` because the surviving directories are an artifact of which files
  # survived, and `sort` because readdir order is not something to assert on.
  case =
    name: src:
    pkgs.runCommandLocal "narrow-sdk-src-${name}"
      {
        manifest = expected;
        passAsFile = [ "manifest" ];
      }
      ''
        (cd ${narrowed src} && find . -type f | sort) > actual
        diff -u "$manifestPath" actual
        touch $out
      '';

  # Interpolating a path yields a store-path string carrying context, and the
  # copy happens during evaluation, so the tree is on disk by the time `narrow`
  # calls `builtins.pathExists` on it. That combination is what makes this the
  # regression guard for the context bug: a derivation would carry context too,
  # but nothing forces it to be built first, so narrowing would quietly bail
  # out and the case would assert nothing. Before the fix this one fails at
  # eval, not at build, with "a string that refers to a store path cannot be
  # appended to a path".
  realizedStorePath = "${builtins.path {
    name = "narrow-sdk-src-fixture";
    path = fixture;
  }}";

  # Stands in for the default fetch: a derivation nothing has built, which
  # `lib.fileset` cannot look inside. Never realized here - the assertion only
  # compares it against what `narrow` handed back.
  unbuilt = pkgs.runCommandLocal "narrow-sdk-src-unbuilt" { } "cp -r ${fixture} $out";
in
assert lib.assertMsg (
  narrowed unbuilt == unbuilt
) "narrowSdkSrc.narrow must return an unbuilt derivation src unchanged";
pkgs.linkFarmFromDrvs "narrow-sdk-src" [
  # A path value, the shape a plain `src = ./.` produces.
  (case "path" fixture)
  (case "store-path-string" realizedStorePath)
  # The shape the README recommends: an explicitly named subset of a checkout.
  (case "fileset-source" (
    lib.fileset.toSource {
      root = fixture;
      fileset = lib.fileset.unions [
        (fixture + "/sdk")
        (fixture + "/README.md")
        (fixture + "/LICENSE")
        (fixture + "/noise.txt")
      ];
    }
  ))
]
