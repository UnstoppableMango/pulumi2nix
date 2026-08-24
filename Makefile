# `integration` names a directory as well as a target, so without this make
# considers it up to date and runs nothing.
.PHONY: build update check lint integration format fmt

build:
	nix build .#

update:
	nix flake update

check lint:
	nix flake check

# Sibling flake, so `nix flake check` above never reaches it. The override is
# what points it at the working tree instead of the last published release, and
# --keep-going reports every failing check rather than stopping at the first.
integration:
	nix flake check ./integration --override-input pulumi2nix . --keep-going

format fmt:
	nix fmt
