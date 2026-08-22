# Exposes every lib/default.nix builder as a top-level pkgs attribute,
# pre-instantiated against `final` so callers don't need to thread `pkgs` manually.
final: prev: import ./default.nix { pkgs = final; }
