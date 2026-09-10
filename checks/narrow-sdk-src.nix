{
  lib,
  pkgs,
  narrowSdkSrc,
}:
let
  fixture = ./fixtures/provider;

  expected = ''
    ./LICENSE
    ./README.md
    ./sdk/nodejs/index.ts
  '';

  narrowed = src: narrowSdkSrc.narrow "nodejs" src { };

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

  realizedStorePath = "${builtins.path {
    name = "narrow-sdk-src-fixture";
    path = fixture;
  }}";

  unbuilt = pkgs.runCommandLocal "narrow-sdk-src-unbuilt" { } "cp -r ${fixture} $out";
in
assert lib.assertMsg (
  narrowed unbuilt == unbuilt
) "narrowSdkSrc.narrow must return an unbuilt derivation src unchanged";
pkgs.linkFarmFromDrvs "narrow-sdk-src" [
  (case "path" fixture)
  (case "store-path-string" realizedStorePath)
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
